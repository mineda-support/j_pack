if $0 == __FILE__
  $: << '.'
  $: << './ade_express'
end
require 'spice_parser'
require 'qucs'
require 'alb_lib'
require 'ngspice'
require 'ltspctl'
require 'ngspctl'
require 'postprocess'
require 'compact_model'
load './customize.rb' if File.exist? './customize.rb'
require 'fileutils'

class EEschemaControl < NgspiceControl
  attr_accessor :elements, :file, :mtime, :pid, :result, :sheet, :netlist, :step_results

  def initialize ckt=nil, ignore_cir=true, recursive=false
    return unless ckt
    @step_results = []
    @ckts = {}
    read ckt, ignore_cir, recursive
    get_models e=@elements[File.basename(@file).sub(/\.\S+/, '')] || @elements 
  end
  
  def read_subckt sheets
    return if sheets.nil? || sheets.empty?
    sht, file = sheets.first
    @sheet[file] ||= read_sch file
    @sheet[file]['sheet_name'] = sht
    sheets.delete sht
    read_subckt sheets
  end
  private :read_subckt

  def open file=@file, ignore_cir=false, recursive=false
    view file 
    read file, ignore_cir, recursive
  end
  
  def view file, options=nil
    work_dir = File.dirname(file)
    Dir.chdir(work_dir){
      pwd = Dir.pwd
      case File.extname file
      when '.kicad_sch'
        if sch_type(file) == 'eeschema'
          command = "#{eeschemaexe} #{options} #{File.basename(file)}"
        else
          raise 'Error: unknown sch file format'
        end
      when '.net', '.spice'
      when ''
      end
      puts "command = #{command}"
      if /mswin32|mingw/ =~ RUBY_PLATFORM
        system 'start "dummy" ' + command # need a dummy title
      else
        @pid = fork do
          exec command
        end
      end
    }
  end

  def read ckt=@file, ignore_cir=false, recursive=false
    if File.exist? ckt
      read0 ckt, recursive # @elements is set
    else
      raise "#{ckt} does not exist!"
    end
    @sheet = {ckt => @elements}
    read_subckt @elements['Sheets'] if @elements && @elements['Sheets']
=begin
    cir = ckt.sub('.kicad_sch', '.cir')
    unless ignore_cir
      if !File.exist? cir
        raise "Error: #{cir} is not available yet --  please open #{ckt}, create nelist and save in #{cir}"
      elsif File.mtime(ckt) > File.mtime(cir)
        raise "Error: #{ckt} is newer than #{cir} --  please open #{ckt}, create nelist and save in #{cir}"
      end
    end
    # @elements = read_net cir if File.exist? cir
=end
    @elements
  end

  def read0 ckt, recursive
    @file = ckt
    case File.extname @file 
    when '.kicad_sch'
        @elements = read_eeschema_sch @file, recursive
    when '.net', '.spice', '.cir', '.spc'
        @elements = read_net @file
        @sheet && @sheet.each_key{|file|
          @sheet[file] = read_eeschema_sch file, recursive
        }
    when ''
      if File.exist? @file+'.kicad_sch'
        @elements = read_sch @file+'.kicad_sch', recursive
      elsif File.exist? @file+'.net'
        @elements = read_net @file+'.net', recursive
      else
      end
    end
    @mtime = Time.now
    puts "elements updated from #{@file}!"
    @elements = @ckts if recursive
    @elements
  end
  private :read0 

  def read_sch file, recursive=false, caller=''
    read_eeschema_sch file, recursive, caller
  end

  def read_eeschema_sch file, recursive=false, caller=''
    puts "read_eeschema_sch reads #{file}"
    require 'sxp'
    elements = {}
    @ckts[File.basename(file).sub(/\.\S+/, '')] = elements if @ckts == {}
    name = type = value = value2 = flag_wire = flag_text = group = nil
    eescm = SXP.read(File.read(file).encode('UTF-8'))
    eescm[1..-1].each{|blk|
      inst = {}
      case blk[0]
      when :text
        blk[1] =~ /^ *\.(\S+)/
        name = $1 || 'netlist'
        elements[name] ||= []
        elements[name] << {control: blk[1]}
      when :symbol
        blk[1..-1].each{|item|
          case item[0]
          when :property
            inst[item[1]] = item[2] # item[1] == 'Reference'
          when :lib_id
            inst['lib_id'] = item[1]
          when :pin
          when :instances
          end
        }
      end
      if name = inst['Reference']
        elements[name] ||= {} 
        if name =~ /^X/
          elements[name][:value] = inst['lib_id'] 
          if recursive
            type = inst['lib_id'].split(':').last
            caller = '.' + name
            target = File.join(File.dirname(file), type + '.kicad_sch')
            if File.exist? target
              @ckts[type] = read_eeschema_sch(target, true, caller)
              #@ckts['eescm'] ||= {}
              #@ckts['eescm'][type] = eescm
              @ckts[caller] = type unless recursive
            end
          end
        else
          elements[name][:value] = inst['Sim.Params'] || inst['Value']
        end
      end
    }
    elements
  end

  def set ckt_pairs
    ckt_pairs.each{|file, pairs|
      update_flag = false
      eescm = SXP.read(File.read(file).encode('UTF-8'))
      eescm[1..-1].each{|blk|
        if blk[0] == :symbol
          ref = nil
          blk[1..-1].each{|item|
            if item[0] == :property
              ref = item[2] if item[1]=='Reference'
              if item[1]=='Sim.Params'
                val = item[2] 
                pairs.each_pair{|p, v| # p is symbol
                  if p.to_s.downcase == ref.downcase
                    item[2] = v.to_s
                    @elements[ref] = "\"#{v.to_s}\""
                    update_flag = true
                  end
                }
              end
            end
          }
        end
      }
      if update_flag
        FileUtils.cp file, file+'_BKUP2'
        File.open(file, 'w'){|f|
          f.puts pretty_sexpr(eescm.to_sxp)
        }
        true
      else
        false
      end
    }
  end

  def simulate *variables
    keys = values = nil
    result = with_stringio{
      keys, values = simulate0 variables
    }
    $stderr.puts 'simulate result:', result, '------'
    [keys, values]
  end

  def call_kicad_netlister kicad_file
    file = kicad_file.sub('.kicad_sch', '.cir').gsub('\\', '/')
    FileUtils.rm(file, force: true) if file && File.exist?(file)
    start = Time.now
    command = "sch export netlist --format spice --output #{file.gsub('\\', '/')}"
    puts "command = #{command}"
    kicad_cli command, kicad_file.gsub('\\', '/')
    wait_for(File.basename(file), start, 'due to some error'){}
    #sleep 1 # weird but file is not available w/o sleep 1
    #
    netlist = File.read(file).encode('UTF-8', invalid: :replace)
  end

  def parse_kicad_file kicad_file, params
    eescm = SXP.read(File.read(kicad_file).encode('UTF-8', invalid: :replace))
    files = []
    update_flag = false
    inst = {}
    step_statement = nil
    eescm[1..-1].each{|blk|
      case blk[0]
      when :text
        if blk[1] =~ /^.subckt +(\S+) +(.*)$/
          subckt_name = $1
          subckt_pins = $2.split("\\n")[0]
          inst['Subckt'] = {subckt_name => subckt_pins}
        elsif blk[1] =~ /\.par/
          blk[1].scan(/(\S+) *= *(\S+)/).each{|a, b| params[a]=b}
        elsif blk[1] =~ /\.inc/
          blk[1].sub!('%HOMEPATH%', "$HOMEPATH\\")
        elsif blk[1] =~ /^[^*]*\.step/  # because KiCad netlister ignores .step statement, pass step_statment to parse
          step_statement = blk[1]
        end
      when :symbol
        blk[1..-1].each{|item|
          case item[0]
          when :property
            inst[item[1]] = item[2] # item[1] == 'Reference'
          when :lib_id
            inst['lib_id'] = item[1]
          end
        }
      end
      if name = inst['Reference']
        # elements[name] ||= {} 
        if name =~ /^X/
          #elements[name][:value] = inst['lib_id'] 
          #if recursive
            type = inst['lib_id'].split(':').last
            files << type # + '.kicad_sch'
            target = File.join(File.dirname(file), type + '.kicad_sch')
            if File.exist? target
              parse_kicad_file target, params
              netlist = call_kicad_netlister target
              inst['Subckt'][type] << netlist.sub('.end', ".ends #{type}\n") 
              update_flag = true
            end
            inst['Reference'] = nil
          #end
        end
      end
    }
    return params unless update_flag

    eescm[1..-1].each{|blk|
      case blk[0]
      when :text
        if blk[1] =~ /^.subckt +(\S+) +(.*)$/
          subckt_name = $1
          subckt_pins = $2.split("\\n")[0]
          if netlist = inst['Subckt'][subckt_name]
            subckt_pins.split.each{|pin|
              netlist.gsub! '/'+pin, pin
            }
            blk[1] = ".subckt #{subckt_name} #{subckt_pins}\n*" + netlist # note: fist line of netlist should be changed to comment
          end
        end
      end
    }
    FileUtils.cp kicad_file, kicad_file+'_BKUP'
    File.open(kicad_file, 'w'){|f|
      f.puts pretty_sexpr(eescm.to_sxp)
    }
    call_kicad_netlister kicad_file
    [params, step_statement]
  end

  def parse file, analysis, step_statement, params={}
    netlist = ''
    steps = []
    home = (ENV['HOMEPATH'] || ENV['HOME'])
    $stderr.puts "file = #{file}"
    control = cont_return = nil
    #File.read(File.basename(file)).encode('UTF-8', invalid: :replace).each_line{|l|
    File.read(file).encode('UTF-8', invalid: :replace).each_line{|l|
      l.chomp!
      l.sub!(/%HOMEPATH%|%HOME%|\$HOMEPATH\\*|\$HOME\\*/, home) # avoid ArgumentError: invalid byte sequence in UTF-8 
      # $stderr.puts "l:#{l}"
      if l =~ /^ *\.*ac +(.*)/
        analysis[:ac] = substitute_params($1, params)
      elsif l =~ /^ *\.*tran +(.*)/
        analysis[:tran] = substitute_params($1, params)
      elsif l =~ /^ *\.*dc +(.*)/
        analysis[:dc] = substitute_params($1, params)
      elsif l =~ /^ *\.endc/
        cont_return = control.dup
        control = nil
      elsif control
        if l.length > 0 && l =~ /meas|let|write/
          control << l + "\n"
        end
      elsif l =~ /^ *\.control/
        control = ''
        netlist << l + "\n"
      elsif l =~/^ *\.end *$/ && step_statement
        steps = step2params(step_statement)
        netlist << '*' + step_statement + "\n.end\n"
      else
        netlist << l + "\n"
      end
    }
    [netlist, steps, cont_return]
  end
  private :parse

  def substitute_params(str, params)
    # { と } に挟まれた、1文字以上の文字（英数字やアンダースコアなど）にマッチ
    str.gsub(/\{([^}]+)\}/) do |match|
      key = $1 # 括弧 () でキャプチャした中身（キー名）を取得
    
      # ハッシュにキーが存在すれば置換、なければ元々のマッチした文字列のままにする
      params.key?(key) ? params[key] : match
    end
  end
  private :substitute_params

  def step2params net
    return nil if net.nil?
    # .step oct param srhr4k  0.8 1.2 3
    # steps['srhr4k'] = {'type' => 'param', 'step' => 'oct', 'values' => [0.8, 1.2, 3]}
    # .step v1 1 3.4 0.5
    # steps['v1'] = {'type' => nil||'src', 'step' => nil||'linear', 'values'..}
    # .step NPN 2N2222(VAF)
    # steps['2N2222_VAF'] = {'type'=>'model', 'step'=>nil, ...}
    steps = []
    net.each_line{|line|
      next unless line =~ /^ *\.step +(.*)$/
      args = $1.split
      step = args.shift
      unless step =~ /lin|oct|dec/
        args.unshift step
        step = 'lin'
      end
      name = args.shift
      type = nil
      if name == 'param'
        type = 'param'
        name = args.shift
      else
        model = args.shift
        if model  =~ /\S+\((\S+)\)/
          type = 'model'
          name = name + '_' + $1+'_'+$2
        else
          args.unshift model
          type = 'src'
          args.shift
        end
      end
      values = args
      if values[0] == 'list'
        step = 'list'
        values.shift # values = ["list", "0.3u", "1u", "3u", "10u"]
      end
      steps << {'name' =>name.downcase, 'type'=>type, 'step'=>step, 'values'=>values}
    }
    steps.reverse
  end
  
  def simulate0 variables
    # system "unix2dos #{@file}" if on_WSL?() # NgspiceXVII saves asc file in LF, but -netlist option needs CRLF!
    file = nil
    netlist = ''
    analysis = {}
    control = nil
    models_update = nil
    extra_commands = ''
    variations = {}
    steps = []
    $stderr.puts "@file = #{@file}"
    params = {}
    if @file =~ /\.sch/ || @file =~ /\.kicad_sch/
      $stderr.puts "sch_type(@file)=#{sch_type(@file)}"
      file = @file.sub '.kicad_sch', '.cir'
      if sch_type(@file) == 'eeschema'
        Dir.chdir(File.dirname @file) {
          params, step_statement = parse_kicad_file @file, params
          netlist, steps, control = parse(file, analysis, step_statement, params)
        }
        $stderr.puts "after parsing, steps ='#{steps}', control =", control, '---' 
        $stderr.puts "#{@file}: #{File.mtime(@file)} vs. #{file}: #{File.mtime(file)}"
        #if File.mtime(@file) > File.mtime(file)
        #  raise "Error: #{@file} is newer than #{file} -- please open #{@file}, create netlist and save in #{file}" 
        #end
        # netlist, steps = super.parse(file, analysys)
      end
    elsif @file =~ /\.cir|\.net|\.spi|\.spice/ 
      netlist, steps, control = super.parse(@file, analysis, '^ *\.step')
    end
    $stderr.puts "netlist = #{netlist}"
    $stderr.puts "analysis = #{analysis}"
    @netlist = netlist
    $stderr.puts "analysis directives in netlist: #{analysis.inspect}" # unless analysis.empty?
    Dir.chdir(File.dirname @file){
      $stderr.puts "variables = #{variables.inspect}"
      if !@ngspice_alive
        Ngspice.init
        @ngspice_alive = true
      end
      Ngspice.circ(netlist)
      variables.each{|v|
        if v.class == Hash
          if v[:models_update]
            models_update = v[:models_update]
            model_lines = get_models @elements
            model_lines && model_lines.each{|lineno|
              lines[lineno-1].sub! '.include', ';include'
            } 
          end
          if v[:variations]
            variations = v[:variations]
            puts "v[:variations]=#{variations}"
          elsif v.first[0] != :probes        
            analysis[v.first[0]] = v.first[1]
          end
        else
          Ngspice.command "save #{v}"
        end
      }
      models_update && models_update.each_pair{|model_name, params|
        params.each_pair{|key, value|
          @models[model_name.to_s][1][key.to_s] = value
        } 
      }

      @step_results = [[], [], [], nil]
      node_list = variables[0] ? variables[0][:probes] : nil
      $stderr.puts "steps = #{steps.inspect}"
      if steps[0] == nil || node_list == nil || node_list == []
        meas_result, r = simulate_core analysis, node_list, control
        @step_results[0] = r[0] if r
        @step_results[1] = r[1] if r
        @step_results[2] = [meas_result.values] if meas_result 
        @step_results[3] = meas_result.keys if meas_result
      else
        step_values = []
        case steps[0]['step']
        when 'lin'
          start, stop, step = steps[0]['values'].map{|v| eng2number(v)}  
          start.step(by: step, to: stop){|v|
            step_values << v
          }
          step_values << stop unless step_values[-1]==stop
        when 'list'
          step_values = steps[0]['values'].map{|v| eng2number(v)}
        end
        
        $stderr.puts "start step analysis with #{step_values.inspect}"
        logs = with_stringio(){
          step_values.each{|v|
            if steps[0]['name'].start_with?('@') || steps[0]['type'] == 'src'
              $stderr.puts "**** alter #{steps[0]['name']}=#{v}"
              Ngspice.command "alter #{steps[0]['name']}=#{v}"
              # Ngspice.command 'reset'
              Ngspice.command 'show ' + steps[0]['name'][1..-1]
            else
              Ngspice.command "alterparam #{steps[0]['name']}=#{v}"
              Ngspice.command 'reset'              
              Ngspice.command 'listing param'
            end
            meas_result, r = simulate_core analysis, node_list, control
            $stderr.puts "node_list = #{node_list}"
            # $stderr.puts "r=#{r.inspect}"
            # r[1][0][:name] = "#{steps[0]['name']}=#{v}" if r[1][0]
            if steps[0] != nil && node_list != nil && node_list != []
              @step_results[0] = r[0]
              r[1].each_with_index{|s, i|
                @step_results[1] << s # r[1][0]
                # r[1][i][:name] << "@#{steps[0]['name']}=#{v}"
                r[1][i][:name] = "#{steps[0]['name']}=#{v}" 
              }
              @step_results[2] ||= []
              @step_results[2] << meas_result.values if meas_result
              @step_results[3] ||= meas_result.keys if meas_result
            end
          }
        }
        $stderr.puts logs
      end
    }
    # @result = Ngspice.get_result
    [@step_results[3], @step_results[2]] 
  end
  
  def kicad_cli arg, input
    puts command = [eeschema_path.gsub('\\', '/').sub('eeschema', 'kicad-cli')] + arg.split(' ') + [input]
    puts "command = #{command}"
    IO.popen command
  end

  def eeschema_path
    if ENV['Eeschema_path'] 
      return ENV['Eeschema_path'] 
    elsif (paths = Dir.glob('KiCad/*/bin/eeschema.exe', base: ENV['PROGRAMFILES'])).length > 0
      return File.join(ENV['PROGRAMFILES'], 
                       paths.max_by{|path| path.match(%r{KiCad/([^/]+)/bin})&.captures&.first.split('.').map(&:to_f)}
                      )
    elsif File.exist?( path =  "#{ENV['PROGRAMFILES']}\\KiCad\\bin\\eeschema.exe")
      return path
    else
      raise 'Cannot find Eeschema executable. Please set Eeschema_path'
    end                     
  end
  #private :eeschema_path

  def eeschema_path_WSL
    path = '/mnt/c/Program Files/KiCad/bin/eeschema.exe'
    return "'#{path}'" if File.exist? path
    nil
  end
  private :eeschema_path_WSL

  def eeschemaexe
    if /mswin32|mingw/ =~ RUBY_PLATFORM
      command = "\"" + eeschema_path() + "\""
    elsif File.directory? '/mnt/c/Windows/SysWOW64/'
      command = eeschema_path_WSL()
    elsif File.exist? "/usr/bin/eeschema"
      command = "/usr/bin/eeschema"
    else
      command = 'flatpak run --command=eeschema org.kicad.KiCad'
    end
    command
  end
  private :eeschemaexe
end
if $0 == __FILE__
  puts Dir.pwd
  Dir.chdir '../j_pack'
  $: << '.'
  $: << './ade_express'
  puts "$: = #{$:}"
  #ckt = NgspiceControl.new file, true, true # test recursive
  #file = File.join 'c:', ENV['HOMEPATH'], "Seafile/Citizen035/Op8_22/Citizen035/EEschema/op8_22_tb_direct_ac.kicad_sch"
  #file = File.join 'c:', ENV['HOMEPATH'], 'Seafile/Op8_18/cdraw/EEschema/op8_18_tb_direct_ac.kicad_sch'
  file = File.join 'c:', ENV['HOMEPATH'], "Seafile/PTS06_2024_8/Op8_18/EEschema/op8_18_tb_direct_ac.kicad_sch"
  #file = File.join 'c:', ENV['HOMEPATH'], "work/alta2_lt2xschm/LDIC_TEG3_DZ4_240925_Digital_Appl/EEschema/AND2_X1_tb.kicad_sch"
  #Dir.chdir(File.join 'c:', ENV['HOMEPATH'], 'Seafile/Citizen035/Op8_22/Citizen035/EEschema')
  Dir.chdir(File.join 'c:', ENV['HOMEPATH'], "Seafile/PTS06_2024_8/Op8_18/EEschema/")
  ckt = EEschemaControl.new file, true, true # false # note: ckt.set (update) does not work with recursive=true
  puts ckt.elements.inspect
  ckt.set({'op8_18_v2.kicad_sch'=> {:V2=>"5.555"}})
  puts ckt.models.inspect
  #ckt.simulate probes: ['frequency', 'V(out)/(V(net1)-V(net3))']
  #r = ckt.get_traces('frequency', 'V(out)/(V(net1)-V(net3))') # [1][0][:y]
  #r = ckt.get_traces('v-swe            ep', 'vds#branch')
  #puts r[1][0][:y] if r[1] && r[1][0]
  #ckt.simulate probes: ['frequency', 'V(out)/(V(net1)-V(net3))'] # probes are necessary for step anaysis
  #r = ckt.get_traces 'v-sweep', 'I(vmeas)'
  #r = ckt.get_traces 'I(vmeas)', 'I(vmeas)'
  #ckt = NgspiceControl.new file, true, true # test recursive
  # r = ckt.get_traces('frequency', 'V(out)') 
  # r = ckt.get_traces('frequency', 'V(out)/(V(net1)-V(net3))') # [1][0][:y]
  #r = ckt.get_traces('v-sweep', 'i(Vds)')
  #r = ckt.get_traces 'v-sweep', 'i(vm0)', 'i(vm1)', 'i(vm2)'
  ckt_pairs = {"op8_18_tb_direct_ac.kicad_sch"=>{"V3"=>1.8}}
  ckt.set ckt_pairs

  ckt.simulate # time', 'v(clk)']
  #r = ckt.get_traces "frequency", "v(/out)/(v(net-_r3-b_)/v(net-_v3-+_))"
  r = ckt.get_traces "frequency", "V(/out)/(V(net-_r3-b_)-V(net-_v3-+_)"
  #r = ckt.get_traces 'time', 'v(clk)'
  puts 'sim end'
end
