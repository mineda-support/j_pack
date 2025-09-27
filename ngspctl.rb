# ngspctl v0.2 Copyright(C) Anagix Corporation
if $0 == __FILE__
  puts Dir.pwd
  Dir.chdir '../j_pack'
  $: << '.'
  $: << './ade_express'
  puts "$: = #{$:}"
  #$: << '/home/anagix/work/alb2/lib'
  #$: << '/home/anagix/work/alb2/ade_express'
  end
require 'spice_parser'
require 'alb_lib'
require 'ngspice'
require 'ltspctl'
require 'postprocess'
require 'compact_model'
load './customize.rb' if File.exist? './customize.rb'
#require 'byebug'
require 'fileutils'

class NgspiceControl < LTspiceControl
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

  def capture ckt=@file
    case File.extname ckt
    when '.asc'
      raise 'not implemented yet'
      return
    when '.sch'
      svg_file = File.basename(ckt).sub('.sch', '.svg')
      view ckt, "--svg --plotfile #{svg_file} -q"
      puts clip="![#{svg_file}](#{svg_file})"
      unless /mswin32|mingw/ =~ RUBY_PLATFORM
        system "echo \"#{clip}\" | xclip -sel clip"
        puts 'Paste the command above in a markdown cell to display the circuit'
      end
    end
  end

  def open file=@file, ignore_cir=false, recursive=false
    view file 
    read file, ignore_cir, recursive
  end
  
  def view file, options=nil
    Dir.chdir(File.dirname file){
      pwd = Dir.pwd
      case File.extname file
      when '.asc'
        command = "#{ltspiceexe} #{options} #{File.basename(file)}"
      when '.sch'
        if sch_type(file) == 'eeschema'
          command = "#{eeschemaexe} #{options} #{File.basename(file)}"
        elsif sch_type(file) == 'xschem'
          command = "#{xschemexe} #{options} #{File.join(pwd, File.basename(file))}" # necessary to pass pwd for xschem
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
    read0 ckt, recursive # @elements is set
    @sheet = nil
    return unless sch_type(ckt) == 'eeschema'
    @sheet = {ckt => @elements}
    read_subckt @elements['Sheets']
    cir = ckt.sub('.sch', '.cir')
    unless ignore_cir
      if !File.exist? cir
        raise "Error: #{cir} is not available yet --  please open #{ckt}, create nelist and save in #{cir}"
      elsif File.mtime(ckt) > File.mtime(cir)
        raise "Error: #{ckt} is newer than #{cir} --  please open #{ckt}, create nelist and save in #{cir}"
      end
    end
    @elements = read_net cir if File.exist? cir
    @elements
  end

  def read0 ckt, recursive
    @file = ckt
    case File.extname ckt 
    when '.asc'
        @elements = read_asc ckt, recursive
    when '.sch'
        @elements = read_sch ckt, recursive
    when '.net', '.spice', '.cir', '.spc'
        @elements = read_net ckt
        @sheet && @sheet.each_key{|file|
          @sheet[file] = read_eeschema_sch file, recursive
        }
    when ''
      if File.exist? ckt+'.asc'
        @elements = read_asc ckt+'.asc', recursive
      elsif File.exist? ckt+'.sch'
        @elements = read_sch ckt+'.sch', recursive
      elsif File.exist? ckt+'.net'
        @elements = read_net ckt+'.net', recursive
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
    if sch_type(file) == 'eeschema'
      read_eeschema_sch file, recursive, caller
    elsif sch_type(file) == 'xschem'
      read_xschem_sch file, recursive, caller
    end
  end
      
  def read_eeschema_sch file, recursive=false, caller=''
    puts "read_eeschema_sch reads #{file}"
    elements = {}
    name = type = value = value2 = flag_wire = flag_text = group = nil
    lineno = 0 
    File.read(file).each_line{|l|
      l.chomp!
      # puts l
      lineno = lineno + 1 
      if flag_wire
        flag_wire = false
      elsif flag_text
        flag_text = false
        control = nil
        if l =~ /^ *(\.(\S+) +.*) */
          control = $1
          name = $2
        elsif l =~ /^ *(;(\S+) +.*) */
          control = $1
          name = $2
        end
        if control
          # puts "control='#{control}' for name=#{name}"
          elements[name] = []
          # puts "elements[name] = #{elements[name]}"
          if control[0] == '.'
            elements[name] <<  {control: control, lineno: lineno}
          else # ';'
            elements[name] <<  {comment: control, lineno: lineno}
          end
          # name = nil
        end
      elsif l =~ /^\$Sheet/
        group = 'Sheets'
      elsif l =~ /^\$Comp/
        group = 'Components'
      elsif l =~ /^Wire/
        flag_wire = true
      elsif l =~ /^Connection/
      elsif l =~ /^Text/
        flag_text = true
      elsif group == 'Components'
        if l =~ /^L (\S+):(\S+) (\S+)/ # Simulation_SPICE:VSIN V1
          name = $3
          type = $2
          elements[name] ||= {}
          elements[name][:type] = type 
        elsif l =~ /^P (\S+) (\S+)/
        elsif l =~ /^F 0 \"(\S+)\" \S+ (\S+) (\S+)/
        elsif l =~ /^F 1 \"(\S+)\" \S+ (\S+) (\S+)/
          elements[name][:value] = $1
          elements[name][:lineno] = lineno
        elsif l =~ /^F [56] \"([^\"]*)\"/
          elements[name][:value] = $1
          elements[name][:lineno] = lineno
        elsif l =~ /\s*((\S+) +(\S+) +(\S+) +(\S+))/
        end
      elsif group == 'Sheets'
        if l =~ /^F0 \"(\S+)\"/ 
          name = $1 
        elsif l =~ /^F1 \"(\S+)\"/
          elements['Sheets'] ||= {}
          elements['Sheets'][name] = $1
        end
      end
    }
    elements
  end

  def read_xschem_sch file, recursive=false, caller=''
    elements = {}
    @ckts[File.basename(file).sub(/\.\S+/, '')] = elements if @ckts == {}
    name = type = value = value2 = control = nil
    lineno = line1 = line2 = 0
    File.exist?(file) && File.read(file).each_line{|l|
      l.chomp!
      lineno = lineno + 1 
      puts "#{lineno}: #{l}"
      if control
        if l =~ /\.endc/
          control = nil
          next
        end 
        if l =~ /^ *\.\S+ +(\S+) *$/ 
          elements['include'] ||= []
          elements['include'] << {control: l, lineno: lineno}
        else
          elements['control'] << {value: l, lineno: lineno}
        end
        next
      elsif l =~ /^C {code_shown.sym} +\S+ +\S+ +\S+ +\S+ {.* value=\"([^"]*)$/
        elements['control'] = []
        control = true
      elsif l =~ /^C {code_shown.sym} +\S+ +\S+ +\S+ +\S+ {.* value=\"(\.(\S+) .*)\"/
        name = $2
        elements[name] ||= []
        elements[name] <<  {control: $1, lineno: lineno}
      elsif l =~ /^C {(\S+).sym} +\S+ +\S+ +\S+ +\S+ {name=(\S+) .*value=(\S+)}/ ||
            l =~ /^C {(\S+).sym} +\S+ +\S+ +\S+ +\S+ {name=(\S+) .*value=\"(.*)\"}/
        type = $1
        name = $2
        value = $3
        elements[name] = {value: value, type: type, lineno: lineno}
      elsif l =~ /^C {(\S+).sym} +\S+ +\S+ +\S+ +\S+ {name=(\S+) +(.*)}/
        type = $1
        name = $2
        value2 = $3
        elements[name] = {value: value2, type: type, lineno: lineno}
        if recursive && name[0].downcase == 'x'
          caller << '.' + name
          @ckts[type] ||= read_xschem_sch(File.join(File.dirname(file), type+'.sch'), true, caller)
          @ckts[caller] = type
        end
      end
    }
    elements['control'] && elements['control'].each_with_index{|c, i|
      elements['control' + i.to_s] = c
    }
    elements.delete 'control'
    # puts "elements:", elements.inspect
    elements
  end

  def read_net file
    puts "read_net reads #{file}"
    elements = {}
    name = type = value = value2 = control = nil
    lineno = line1 = line2 = 0 
    #    File.read(file).encode('UTF-8', invalid: :replace).each_line{|l|
    File.read(file).each_line{|l|
      l.chomp!
      lineno = lineno + 1 
      if control
        if l =~ /\.endc/
          control = nil
          next
        end 
        # l =~ /(\S+) (.*$)/
        elements['control'] << {value: l, lineno: lineno}
        next
      elsif l=~ /^ *([Ll]\S*) +\((.*)\) +(\S+) +(.*) *$/ ||
         l=~ /^ *([Ll]\S*) +(\S+ \S+) +(\S+) +(.*) *$/ ||
         l=~ /^ *([Ll]\S*) +\((.*)\) *$/ ||
         l=~ /^ *([Ll]\S*) +(\S+ \S+) *$/
        puts 'not implemented yet'
      elsif l=~ /^ *([Xx]*[Cc]\S*) +\((.*)\) +(\S+) +(.*) *$/ ||
            l=~ /^ *([Xx]*[Cc]\S*) +(\S+ \S+) +(\S+) +(.*) *$/ ||
            l=~ /^ *([Xx]*[Cc]\S*) +\((.*)\) +(.*) *$/ ||
            l=~ /^ *([Xx]*[Cc]\S*) +(\S+ \S+) +(.*) *$/
        elements[$1] = {value: $3, lineno: lineno}
      elsif l=~ /^ *([Xx]*[Rr]\S*) +\((.*)\) +(\S+) +(.*) *$/ ||
            l=~ /^ *([Xx]*[Rr]\S*) +(\S+ \S+) +(\S+) +(.*) *$/ ||
            l=~ /^ *([Xx]*[Rr]\S*) +\((.*)\) +(.*) *$/ ||
            l=~ /^ *([Xx]*[Rr]\S*) +(\S+ \S+) +(.*) *$/
        elements[$1] = {value: $3, lineno: lineno}
      elsif l=~ /^ *([Dd]\S*) +\(([^\)]*)\) +(\S+) +(.*) *$/ ||
            l=~ /^ *([Dd]\S*) +(\S+ \S+) +(\S+) +(.*) *$/
      elsif l=~ /^ *([Qq]\S*) +\(([^\)]*)\) +(\S+) +(.*) *$/ ||
            l=~ /^ *([Qq]\S*) +(\S+ \S+ \S+) +(\S+) +(.*) *$/
      elsif l=~ /^ *([Mm]\S*) +\(([^\)]*)\) +(\S+) +(.*) *$/ ||
            l=~ /^ *([Mm]\S*) +(\S+ \S+ \S+ \S+) +(\S+) +(.*) *$/
        elements[$1] = {type: $3, value: $4, lineno: lineno}
      elsif l=~ /^ *([Jj]\S*) +\(([^\)]*)\) +(\S+) +(.*) *$/ ||
          l=~ /^ *([Jj]\S*) +(\S+ \S+ \S+) +(\S+) +(.*) *$/
        puts 'not implemented yet'
      #elsif l=~ /^ *([VvIi]\S*) +\((.*)\) +(\S+) (AC|ac) *=* *(\S+) *$/ ||
      #    l=~ /^ *([VvIi]\S*) +(\S+ \S+) +(\S+) (AC|ac) *=* *(\S+) *$/
      #  elements[$1] = {value: $3, lineno: lineno}
      elsif l=~ /^ *([VvIi]\S*) +\((.*)\) +(.*) *$/ ||
          l=~ /^ *([VvIi]\S*) +(\S+ \S+) +(.*) *$/
        elements[$1] = {value: $3, lineno: lineno}
      elsif l=~ /^ *([Ee]\S*) +(\(.*\)) +(\S+) +(.*) *$/ ||
          l=~ /^ *([Ee]\S*) +(\S+ \S+) +(\S+) +(.*) *$/
        puts 'not implemented yet'
      elsif l=~ /^ *([Ff]\S*) +(\(.*\)) +(\S+) +(.*) *$/ ||
          l=~ /^ *([Ff]\S*) +(\S+ \S+) +(\S+) +(.*) *$/
        puts 'not implemented yet'
      elsif l=~ /^ *([Gg]\S*) +(\(.*\)) +(\S+) +(.*) *$/ ||
          l=~ /^ *([Gg]\S*) +(\S+ \S+) +(\S+) +(.*) *$/
        puts 'not implemented yet'
      elsif l=~ /^ *([Hh]\S*) +(\(.*\)) +(\S+) +(.*) *$/ ||
            l=~ /^ *([Hh]\S*) +(\S+ \S+) +(\S+) +(.*) *$/
        puts 'not implemented yet'
      elsif l =~ /^ *(\.(\S+) +.*) *$/
        puts "l=#{l}"
        control = $1
        name = $2
        if control
          elements[name] = []
          # puts "elements[name] = #{elements[name]}"
          if control[0] == '.'
            elements[name] <<  {control: control[1..-1], lineno: lineno}
          else
            elements[name] <<  {comment: control[1..-1], lineno: lineno}
          end
        end
        control = nil
      elsif l =~ /control/
        elements['control'] = []
        control = true
      end
    }
    elements
  end
  private :read_net

  def set pairs
    if @file =~ /\.asc/
      super pairs
    else
      if @sheet && !@sheet.empty?
        cir = @file.sub('.sch', '.cir')
        @sheet.each_key{|file|
          puts "#{file}: #{File.mtime(file)} vs. #{cir}: #{File.mtime(cir)}"
          if File.mtime(file) > File.mtime(cir)
            raise "Error: #{file} is newer than #{cir} -- please open #{file}, create netlist and save in #{cir}" 
          end
          lines, result2 = set0 pairs, file, @sheet[file], @mtime
          result2.delete false
          update(file, lines) unless result2.empty? # all false
        }
        file = cir
      else
        file = @file
      end
      e = @elements[File.basename(@file).sub(/\.\S+/, '')] || @elements
      lines, result = set0 pairs, file, e, @mtime
      update(file, lines) 
      result
    end
  end

  def set0 pairs, file, elements, mtime
    read file if File.mtime(file) > mtime
    puts "set0 '#{pairs}' in '#{file}' with elements:#{elements.inspect}"  
    lines = File.read(file)
    if lines.include? "\r\n"
      lines = lines.split("\r\n")
    else
      lines = lines.split("\n")
    end
    result = pairs.map{|sym, val|
      name = sym.to_s
      # debugger if name == 'VD'
      value = val.to_s
      # puts "set #{name}: #{value}"
      if elements[name] && elements[name].class == Hash
        lineno = elements[name][:lineno]
        line = lines[lineno-1]
        puts "line: #{line}"
        if line =~ /(^C {\S+.sym} +\S+ +\S+ +\S+ +\S+ {name=\S+ .*value=)(\S+)(})/ || # for xschem
           line =~ /(^C {\S+.sym} +\S+ +\S+ +\S+ +\S+ {name=\S+ .*value=\")(.*)(\"})/ ||
           line =~ /(F 1 \")([^\"]*)(\")/ || # for eeschema
           line =~ /(^ *[Mm]\S* +\([^\)]*\) +\S+ +)(.*)( *)/ || # for netlist
           line =~ /(^ *[Mm]\S* +\S+ \S+ \S+ \S+ +\S+ +)(.*)( *)/ ||
           line =~ /(^ *[VvIiCcRr]\S* +\S+ +\S+ +)(.*)( *)/
          substr = $2
          #puts "***before:'#{lines[lineno-1]}'"          
          line.sub! line, "#{$1}#{value}#{$3}"
          elements[name][:value].sub!(substr, value)
          #puts "***after:'#{lines[lineno-1]}'"
        elsif line =~ /(^C {\S+.sym} +\S+ +\S+ +\S+ +\S+ {name=\S+ +)(.*)(})/ # for xschem
          substr = $2
          if value[0] == '-'
            value = sub substr, value[1..-1]
          elsif value[0] == '+'
            value = add substr, value[1..-1]
          end
          line.sub! line, "#{$1}#{value}#{$3}"
          elements[name][:value].sub!(substr, value)
        else
          line.sub! line, value
          elements[name][:value].sub!(line, value)
        end
        true
      else
        # puts "name=#{name} for file:#{file}"
        name =~ /(\S+)_(\d+)/ 
        elm = ($1 && elements[$1]) ? elements[$1][$2.to_i-1] : elements[name] && elements[name][0]
        if elm && lineno = elm[:lineno]
          line = lines[lineno-1]
          # puts line
          if line =~ /(^C {code_shown.sym} +\S+ +\S+ +\S+ +\S+ {.* value=\")(\.\S+ .*)(\")/  # for xschem
            line.sub! line, "#{$1}#{value}#{$3}"
            elm[:control] = value
            true
          elsif line =~ /(^ *)([\.;]#{name}.*)$/ # for eeschema and netlist 
            line.sub! line, value
            elm[:control] = value
            true
          else
            false
          end
        else
          puts "Error: #{name} was not found in #{file}"
          # puts "elements=#{elements.inspect}"
          false
        end
      end
    }
    [lines, result]
  end
  
  def update file=@file, lines
    if file =~ /\.asc/
      super file, lines
    else
      File.open(file, 'w'){|f| f.puts lines}
      @mtime = File.mtime(file)          
    end
  end
  private :update
=begin
  def emulated_step_analysis step_desc = '.step param ccap 0.2p 1p 0.5p', node_list = ['frequency', 'V(out)/(V(net1)-V(net3))']
    steps = LTspice.new.step2params(step_desc)
    return nil if steps[0].nil?
    start, stop, step = steps[0]['values'].map{|v| eng2number(v)}
    results = [[], []]
    logs = with_stringio(){
      start.step(by: step, to: stop){|v|
        if steps[0]['name'].start_with '@'
          Ngspice.command "alter #{steps[0]['name']}=#{v}"
        else
          Ngspice.command "alterparam #{steps[0]['name']}=#{v}"
        end
        Ngspice.command 'reset'
        Ngspice.command 'listing param'
        Ngspice.command 'run'
        r = get_active_traces *node_list
        results[0] = r[0]
        results[1] << r[1]
      }
    }
    $stderr.puts logs
    results
  end
=end

  def simulate *variables
    keys = values = nil
    result = with_stringio{
      keys, values = simulate0 variables
    }
    $stderr.puts 'simulate result:', result, '------'
    [keys, values]
  end

  def parse file, analysis, comment_step=nil
    netlist = ''
    steps = []
    home = (ENV['HOMEPATH'] || ENV['HOME'])
    $stderr.puts "file = #{file}"
    control = cont_return = nil
    File.read(file).encode('UTF-8', invalid: :replace).each_line{|l|
      l.chomp!
      l.sub!(/%HOMEPATH%|%HOME%|\$HOMEPATH\\*|\$HOME\\*/, home) # avoid ArgumentError: invalid byte sequence in UTF-8 
      # $stderr.puts "l:#{l}"
      if l =~ /^ *\.*ac +(.*)/
        analysis[:ac] = $1
      elsif l =~ /^ *\.*tran +(.*)/
        analysis[:tran] = $1
      elsif l =~ /^ *\.*dc +(.*)/
        analysis[:dc] = $1
      elsif comment_step && l =~ /#{comment_step}/
        steps = step2params(l)
        netlist << '*' + l + "\n"
        $stderr.puts "commented: #{l}"
      elsif l =~ /^ *\.endc/
        cont_return = control.dup
        control = nil
      elsif control
        if l.length > 0 && l =~ /meas|let|write/
          control << l + "\n"
        end
      elsif l =~ /^ *\.control/
        control = ''
      else
        netlist << l + "\n"
      end
    }
    [netlist, steps, cont_return]
  end
  private :parse

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
      steps << {'name' =>name, 'type'=>type, 'step'=>step, 'values'=>values}
    }
    steps.reverse
  end
  
  def simulate0 variables
    # system "unix2dos #{@file}" if on_WSL?() # NgspiceXVII saves asc file in LF, but -netlist option needs CRLF!
    file = nil
    netlist = ''
    analysis = {}
    control = nil
    steps = []
    $stderr.puts "@file = #{@file}"
    if @file =~ /\.asc/
      file = @file.sub('.asc', '.net')
      FileUtils.rm(file, force: true) if File.exist? file
      Dir.chdir(File.dirname @file){ # chdir or -netlist does not work 
        FileUtils.cp @file, @file.sub('.asc', '.tmp')
        run_ltspice '-netlist', File.basename(@file.sub('.asc', '.tmp'))
        wait_for File.basename(file), Time.now, 'due to some error'
      }
      File.open(file, 'r:Windows-1252').read.encode('UTF-8').gsub(181.chr(Encoding::UTF_8), 'u').each_line{|l|
        if l =~ /^\.tran +(\S+)/
          tstop = $1
          netlist << l.sub(tstop, "#{eng2number(tstop)/100.0} #{tstop}")
        elsif l =~ /^\.(back|lib|model)/
          netlist << l.sub(/^/, '*')
        else
          netlist << l
        end
      }
    elsif @file =~ /\.sch/
      $stderr.puts "sch_type(@file)=#{sch_type(@file)}"
      if sch_type(@file) == 'eeschema'
        file = @file.sub('.sch', '.cir')
        $stderr.puts "#{@file}: #{File.mtime(@file)} vs. #{file}: #{File.mtime(file)}"
        if File.mtime(@file) > File.mtime(file)
          raise "Error: #{@file} is newer than #{file} -- please open #{@file}, create netlist and save in #{file}" 
        end
        netlist, steps = super.parse(file, analysys)
      elsif sch_type(@file) == 'xschem'
        Dir.chdir(File.dirname @file){
          pwd = Dir.pwd
          file = @file.sub '.sch', '.spice'
          #File.delete file if file && File.exist?(file)
          FileUtils.rm(file, force: true) if file && File.exist?(file)
          start = Time.now
          run "-s -n -x -q -o .", File.join(pwd, File.basename(@file)) # passing only @file causes load_schematic(): unable to open file
            # xschem options:
            # -s: set netlist type to spice
            # -n: create netlist
            # -i: do not load any xschemrc file
            # -x: command mode (no X)
            # -q: quit after doing things 
            # -o: output directory
          wait_for File.basename(file), start, 'due to some error'
          sleep 1 # weird but file is not available w/o sleep 1
          netlist, steps, control = parse(file, analysis, '^ *\.step')
          #$stderr.puts "after parsing steps\n#{netlist}"
          $stderr.puts "after parsing, steps ='#{steps}', control =", control, '---'
        }
      end
    elsif @file =~ /\.cir|\.net|\.spi|\.spice/ 
      netlist, steps, control = parse(@file, analysis, '^ *\.step')
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
=begin
          if v[:models_update]
            models_update = v[:models_update]
            model_lines = get_models @elements
            model_lines.each{|lineno|
              lines[lineno-1].sub! '.include', ';include'
            } 
          end
          if v[:variations]
            variations = v[:variations]
            puts "v[:variations]=#{variations}"
          else        
            analysis[v.first[0]] = v.first[1]
          end
=end
        else
          Ngspice.command "save #{v}"
        end
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
            @step_results[0] = r[0]
            r[1].each_with_index{|s, i|
              @step_results[1] << s # r[1][0]
              r[1][i][:name] << "@#{steps[0]['name']}=#{v}"
            }
            @step_results[2] ||= []
            @step_results[2] << meas_result.values
            @step_results[3] ||= meas_result.keys
          }
        }
        $stderr.puts logs
      end
    }
    # @result = Ngspice.get_result
    [@step_results[3], @step_results[2].transpose] # return transposed array
  end

  def simulate_core analysis, node_list, control = ''
    $stderr.puts "control in simulate_core: #{control}", '---'
    if analysis.empty?
      error_messages = ''
      with_stringio(){
        Ngspice.command('run')
      }.each_line{|l|
        # $stderr.puts "l: #{l}"
        error_messages << l if l =~ /Error/
      }
      raise error_messages if error_messages.length > 0
    else
      $stderr.puts "analysis = #{analysis.inspect}"
      meas_result = nil
      analysis.each{|k, v|
        error_messages = ''
        with_stringio(){
          Ngspice.command "#{k} #{v.downcase}" # do not know why but must be lowercase
        }.each_line{|l|
          puts "l=>#{l}"
          error_messages << l if l =~ /Error/
          if meas_result
            if l =~ /^stdout +(\S+) += +(\S+)/
              meas_result[$1] = $2 if $1
            end
          elsif l =~ /^stdout *Measurements +for +Transient +Analysis/
            meas_result = {}
          end
        }
        $stderr.puts "meas_result: #{meas_result.inspect}"
        #raise error_messages if error_messages.length > 0
      }
    end  
    #sleep 1
    r = nil
    if node_list.length > 1
      if node_list[0] == 'frequency'
        r = get_AC_traces *node_list
      else
        r = get_active_traces *node_list
      end
    end
    if control && control.length > 0
      meas_result = {}
      with_stringio(){
        control.each_line{|c|
          Ngspice.command c
          if c =~ /let +(\S+)/
            Ngspice.command "print #{$1}"
          end
        }
      }.each_line{|l|
        puts "l=>#{l}"
        if l =~ /^stdout +(\S+) += +(\S+)/
          meas_result[$1] = $2
        end
      }
    end
    #Ngspice.command 'set nomoremode'
    [meas_result, r]
  end

  def sim_log ckt=@file # should be revised!
    File.read(ckt.sub('.asc', '.log')).gsub("\x00", '')
  end
  
  def with_stringio
    require 'stringio'
    stdout_keep = $stdout
    $stdout = StringIO.new
    yield
    $stdout.flush ### flush does not seem to work
    result = $stdout.string
    $stdout = stdout_keep
    result.dup
  end
  def info
    puts '*** info entered ***'
    result = nil
    unless @scale_var
      with_stringio(){
        Ngspice.command 'setscale'
      } =~ /stdout *(\S+)/
      @scale_var = $1
    end
    puts "@scale_var = '#{@scale_var}' @info before calling Ngspice.info"
    with_stringio(){
      Ngspice.info
    }.each_line{|l|
      if result && l =~ /stdout *(\S+) */
        result << $1 if $1 != @scale_var
      elsif l =~ /stdout Date:/
        result = []
      end
    }
    [@scale_var].concat result
  end
  
  def plot *node_list
    require 'rbplotly'

    layout_overwrite = nil
    vars = node_list.delete_if{|a| a.is_a?(Hash) && layout_overwrite ||=  a[:layout]}

    layout = {title: "#{vars[1..-1].join(',')} vs. #{vars[0]}",
              yaxis: {title: vars[1..-1].join(',')},
              xaxis: {title: vars[0]}}
    layout.merge! layout_overwrite if layout_overwrite

    vars, traces = get_traces *node_list

    if vars[0] =~ /frequency/
      # puts "vars[1]:#{vars[1]}"
      layout[:xaxis][:type] = 'log' 
      if vars[1] =~ /^ph\(/
        phase = traces.map{|trace| {x: trace[:x], y: trace[:y].map{|a| shift360(180.0*a/Math::PI)}}}
        traces = phase
      end
    end
    # puts "vars=#{vars}; layout: #{layout}"
    pl = Plotly::Plot.new data: traces, layout: layout
    pl.show
    nil
  end

  def translate a
    unless @sheet.nil? || @sheet.empty? # variable need to be converted like '/sheet602621c0/out
      b= (a=~/\(([^\(\)]+)\)/) ? $1 : a
      c = b.split('/')
      return b if c[0] == '' || c.size == 1
      d = (c[0..-2].map{|e|
             if e =~ /^#([0-9]+) *$/
               @sheet.to_a[$1.to_i][1]['sheet_name'] || e
             else
               e
             end
           } + [c.last]).join('/')
      a.sub! b, '/' + d
    else
      a
    end
  end
  private :translate
  
  def node_list_to_variables node_list, get_active_traces=true
    variables = [node_list[0]]
    node_list[1..-1].each{|a|
      a.strip!
      if a =~ /#{pattern='[vV]*\(([^\)\("]*)\)'}/
        a.gsub(/#{pattern}/){"\"#{translate $1}\""}
      elsif (a=~ /#{pattern='\("([^()]+)"\)'}/) || (a=~ /#{pattern='\(([^()]+)\)'}/)
        a.gsub(/#{pattern}/){"(\"#{translate $1}\")"} # change db(/sheet1/out1') ph(/in') -> db("/sheet1/out1") ph("/in")
      #elsif a =~ /^[^"]\S*[+-\/]\S*/  # wrap with double quote if name is like: 'in-'
      #  a = '"' + a + '"'        
      elsif a=~ /#{pattern='(\S+)($| +[\*\/\-\+$])'}/
        a.gsub(/#{pattern}/){"(\"#{translate $1}\")"}
      else
        "\"#{translate a}\""
      end
      if variables[0] == 'frequency' && get_active_traces
        variables << "real(#{a})"
        variables << "imag(#{a})"
      else
        variables << a
      end
    }
    variables
  end
  private :node_list_to_variables

  def get_traces *node_list
    # require 'debug'; debugger
    return [[], []] if node_list.size <= 1
    if @step_results && @step_results[0].size > 0
      [@step_results[0],  @step_results[1]] # should return [vals, r]
    else
      if node_list[0] == 'frequency'
        get_AC_traces *node_list
      else
        get_active_traces *node_list
      end
    end
  end

  def get_AC_traces *node_list
    info_a = info()
    vars = info_a[1..-1].map{|eq|
      if eq =~ /(.+)#branch/
        "i(#{$1})"
      else
        "v(#{eq})"
      end
    }.unshift(info_a[0])
    $stderr.puts "vars=#{vars}"
    equations = node_list_to_variables(node_list, false).map{|a| a.downcase}
    $stderr.puts "equations=#{equations} @ get_AC_traces"  # ['frequency', 'v(out) /(v(net3)-V(net1))']
    equations_joined = equations.join(',')
    variables = vars.select{|v| equations_joined.include? v} # ['frequency', 'v(out)', 'v(net3)', 'v(net1)']
    $stderr.puts "variables=#{variables}"
    equations.each{|eq|
      variables[1..-1].each_with_index{|v, i|
        val = v.sub(/\(/, '\(').sub(/\)/, '\)')
        if eq =~ /[\*\+-\/\(]*#{val}[\*\+-\/\)]*/ 
          eq.gsub! v, "Complex(v_values[#{2*i+1}][j], v_values[#{2*i+2}][j])" 
        end
      } #['frequency', 'Complex(values[0], values[1]) /(Complex(values[2], values[3])-Complex(values[4], values[5]))']
    }
    $stderr.puts "eval equations=#{equations}"
    # @result = Ngspice.get_result variables[1..-1].map{|a| ["real(#{a})", "imag(#{a})"]}.flatten
    v_values = []
    variables[1..-1].each{|a|
      result = Ngspice.get_result ["real(#{a})", "imag(#{a})"] # suprisingly get_result works for only one complex signal
      h_values = []
      result.map{|h| h.values}.each{|values| # h is hash, so h.keys and h.values
        h_values << values[1..-1].map{|v| v.to_f}
      }
      v_values.concat ((v_values == [])? h_values.transpose[0..2] : h_values.transpose[1..2])
    }
    traces = []
    equations[1..-1].each_with_index{|eq, i|
      traces << {x: Array_with_interpolation.new, y: Array_with_interpolation.new, 
                 name: eq}
      traces[i][:x] = v_values[0]
      traces[i][:y] = []
      for j in 0..v_values[0].length-1
        traces[i][:y][j] = eval(eq)
      end
    }
    [variables, traces]
  end

  def get_active_traces *node_list
    info_a = info()
    vars = info_a[1..-1].map{|eq|
      if eq =~ /(.+)#branch/
        "i(#{$1})"
      else
        "v(#{eq})"
      end
    }.unshift(info_a[0])
    $stderr.puts "vars=#{vars}"
     variables = node_list_to_variables(node_list).map{|a| a.downcase}
    $stderr.puts "variables=#{variables} @ get_active_traces"
    equations_joined = variables.join(',')
    vars = vars.select{|v| equations_joined.include? v} # variables used in equations
    equation = variables[0]
    # variables << variables[0] if variables[0] != vars[0]
    vars.each{|v|
      val = v.sub(/\(/, '\(').sub(/\)/, '\)')
      if v == info_a[0]
        equation.gsub! v, "values[0]"
      elsif equation =~ /[\*\+-\/\(]*#{val}[\*\+-\/\)]*/ 
        unless index = variables.find_index(v)
          variables << v
          index = variables.length - 1
        end
        equation.gsub! v, "values[#{index + 1}]"
      end
    }
    @result = Ngspice.get_result variables[1..-1]
    # $stderr.puts @result
    indices = []
    vars = []
    traces = []
    # variables.delete 'v-sweep'
    # rc = true if variables[0] == 'frequency'
    node_list.each_with_index{|name, i|
      #if variables.include? name
        indices <<  i
        if variables[0] == 'frequency' && name =~ /real\((.*)\)/
            vars << $1
        else
          vars << name
        end
      #end
    }
    old_index = index = -100000
    count = 0
    trend = 0
    old_value = nil
    @result.map{|h| h.values}.each{|values| # h is hash, so h.keys and h.values
      index = values[0].to_i
      values = values[1..-1].map{|v| v.to_f}
      # puts "index: #{index} > old_index: #{old_index}"
      break if index < old_index
      if old_value != nil && trend == 0
          trend = 1 if values[0] > old_value
          trend = -1 if values[0] < old_value
      elsif old_value.nil? || (trend > 0 && values[0] < old_value) || (trend < 0 && values[0] > old_value)
          count = traces.size
        (variables.size-1).times{|i|
          traces << {x: Array_with_interpolation.new, y: Array_with_interpolation.new, 
                     name: vars[i+1]? vars[i+1].gsub('"', '') : "#{i+1}"}
        }
        trend = 0
        old_value = nil
      end
      indices[1..node_list.length-1].each_with_index{|j, i|
        if variables[0] == 'frequency' 
          if i % 2 == 0
            if index == 0
              traces << {x: Array_with_interpolation.new, y: Array_with_interpolation.new, name: vars[i+1].gsub('"', '')}
            end
            traces[count+i/2][:x] << values[0]
            traces[count+i/2][:y] << Complex(values[j], values[j+1])
          end
        else
          traces[count+i][:x] << eval(equation)
          traces[count+i][:y] << values[j]
        end
      }
      old_index = index
      old_value = values[0].to_f
    }
    [vars, traces]
  end

  def run_ltspice arg, input
    puts command = "#{ltspiceexe} #{arg} \"#{input}\""
    # system command
    IO_popen command
  end

  def run arg, input
    puts command = "#{xschemexe} #{arg} #{input}"
    # system command
    IO_popen command
  end

  def sch_type file # either 'xschem' or 'eeschema'
    # puts "file=#{file} @Dir.pwd = #{Dir.pwd}"
    File.open(file){|f|
      line = f.gets 
      return 'xschem' if line =~ /xschem/
      return 'eeschema' if line =~ /EESchema/
    }
    nil
  end
      
  def xschem_path
    if ENV['Xschem_path'] 
      return ENV['Xschem_path'] 
    elsif File.exist?( path =  "#{ENV['PROGRAMFILES']}\\Xschem\\bin\\Xschem.exe")
      return path
=begin
    elsif File.exist?( path =  "#{ENV['PROGRAMFILES']}\\LTC\\XschemXVII\\XVIIx86.exe")
      return path
    elsif File.exist?( path =  "#{ENV['ProgramFiles(x86)']}\\LTC\\XschemIV\\scad3.exe")
      return path
=end
    else
      raise 'Cannot find Xschem executable. Please set Xschem_path'
    end                     
  end
  private :xschem_path

  def xschem_path_WSL
    ['/mnt/c/Program Files/LTC/XschemXVII/XVIIx64.exe',
     '/mnt/c/Program Files (x86)/LTC/XschemIV/scad3.exe'].each{|path|
      return "'#{path}'" if File.exist? path
    }
    nil
  end
  private :xschem_path_WSL

  def xschemexe
    if /mswin32|mingw/ =~ RUBY_PLATFORM
      command = "\"" + xschem_path() + "\""
    elsif File.directory? '/mnt/c/Windows/SysWOW64/'
      command = xschem_path_WSL()
    else
      command = "/usr/local/bin/xschem"
    end
    command
  end
  private :xschemexe

  def eeschema_path
    if ENV['Eeschema_path'] 
      return ENV['Eeschema_path'] 
    elsif File.exist?( path =  "#{ENV['PROGRAMFILES']}\\KiCad\\bin\\eeschema.exe")
      return path
    else
      raise 'Cannot find Eeschema executable. Please set Eeschema_path'
    end                     
  end
  private :eeschema_path

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
    else
      command = "/usr/bin/eeschema"
    end
    command
  end
  private :eeschemaexe
end
if $0 == __FILE__
  file = File.join 'c:', ENV['HOMEPATH'], 'work/Op8_18/Xschem/op8_18_tb_direct_ac.sch'
  #file = File.join 'c:', ENV['HOMEPATH'], 'work/Op8_18/Xschem/op8_18_tb_direct_ac.spice'
  #file = File.join 'c:', ENV['HOMEPATH'], 'work\Op8_18\Xschem\simulation\op8_18_tb_direct_ac.spice'
  #file = File.join 'c:', ENV['HOMEPATH'], 'Seafile/MinimalFab/work/SpiceModeling/Xschem/Idvd_nch_pch.spice'
  #file = File.join 'c:', ENV['HOMEPATH'], 'work/TAMAGAWA/test/simulation/MNO_parameter_different.spice'
  #file = File.join 'c:', ENV['HOMEPATH'], 'work/TAMAGAWA/test/MPO_parameter_different.spice'
  #file = File.join 'c:', ENV['HOMEPATH'], 'KLayout/salt/IP62/Samples/test_devices/Xschem/pmos.sch'
  #file = File.join 'c:', ENV['HOMEPATH'], 'work/TAMAGAWA/test/Idvd_MNO_MPO.sch'
  #file = File.join 'c:', ENV['HOMEPATH'], '/Seafile/斎藤さんのNGspice検証/Xschem/test_MPO_3.sch'
  #file = 'c:/tmp/VTH_VBG1.sch'

  #ckt = NgspiceControl.new file, true, true # test recursive
  ckt = NgspiceControl.new file, true, false # note: ckt.set (update) does not work with recursive=true
  puts ckt.elements.inspect
  #ckt.set({:VD=>"0.05"})
  puts ckt.models.inspect
  #ckt.simulate probes: ['frequency', 'V(out)/(V(net1)-V(net3))']
  #r = ckt.get_traces('frequency', 'V(out)/(V(net1)-V(net3))') # [1][0][:y]
  #r = ckt.get_traces('v-swe            ep', 'vds#branch')
  #puts r[1][0][:y] if r[1] && r[1][0]
  ckt.simulate probes: ['frequency', 'V(out)/(V(net1)-V(net3))'] # probes are necessary for step anaysis
  #r = ckt.get_traces 'v-sweep', 'I(vmeas)'
  #r = ckt.get_traces 'I(vmeas)', 'I(vmeas)'
  #ckt = NgspiceControl.new file, true, true # test recursive
  r = ckt.get_traces('frequency', 'V(out)') 
  r = ckt.get_traces('frequency', 'V(out)/(V(net1)-V(net3))') # [1][0][:y]
  #r = ckt.get_traces('v-sweep', 'i(Vds)')
  #r = ckt.get_traces 'v-sweep', 'i(vm0)', 'i(vm1)', 'i(vm2)'
  puts 'sim end'
end
