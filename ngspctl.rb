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
load 'spice_parser.rb'
load 'alb_lib.rb'
load 'ngspice.rb'
load 'ltspctl.rb'
load 'postprocess.rb'
load 'compact_model.rb'
load './customize.rb' if File.exist? './customize.rb'
#require 'byebug'
require 'fileutils'

class NgspiceControl < LTspiceControl
  attr_accessor :elements, :file, :mtime, :pid, :result, :sheet, :netlist
  @@step_results = {}

  def initialize ckt=nil, ignore_cir=true, recursive=false
    return unless ckt
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
      case File.extname file
      when '.asc'
        command = "#{ltspiceexe} #{options} #{File.basename(file)}"
      when '.sch'
        if sch_type(file) == 'eeschema'
          command = "#{eeschemaexe} #{options} #{File.basename(file)}"
        elsif sch_type(file) == 'xschem'
          command = "#{xschemexe} #{options} #{File.basename(file)}"
        else
          raise 'Error: unknown sch file format'
        end
      when '.net', '.spice'
      when ''
      end
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
    name = type = value = value2 = nil
    lineno = line1 = line2 = 0 
    File.read(file).each_line{|l|
      l.chomp!
      lineno = lineno + 1 
      if l =~ /^C {code_shown.sym} +\S+ +\S+ +\S+ +\S+ {.* value=\"(\.(\S+) .*)\"/
        name = $2
        elements[name] ||= []
        elements[name] <<  {control: $1, lineno: lineno}
      elsif l =~ /^C {(\S+).sym} +\S+ +\S+ +\S+ +\S+ {name=(\S+) .*value=(\S+)}/
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
    elements
  end

  def read_net file
    puts "read_net reads #{file}"
    elements = {}
    name = type = value = value2 = nil
    lineno = line1 = line2 = 0 
    #    File.read(file).encode('UTF-8', invalid: :replace).each_line{|l|
    File.read(file).each_line{|l|
      l.chomp!
      lineno = lineno + 1 
      if l=~ /^ *([Ll]\S*) +\((.*)\) +(\S+) +(.*) *$/ ||
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
      lines, result = set0 pairs, file, @elements, @mtime
      update(file, lines) 
      result
    end
  end

  def set0 pairs, file, elements, mtime
    read file if File.mtime(file) > mtime
    # puts "set0 '#{pairs}' in '#{file}' with elements:#{elements}"  
    lines = File.read(file)
    if lines.include? "\r\n"
      lines = lines.split("\r\n")
    else
      lines = lines.split("\n")
    end
    result = pairs.map{|sym, val|
      name = sym.to_s
      #debugger if name == 'C3'
      value = val.to_s
      # puts "set #{name}: #{value}"
      if elements[name] && elements[name].class == Hash
        lineno = elements[name][:lineno]
        line = lines[lineno-1]
        if line =~ /^C {\S+.sym} +\S+ +\S+ +\S+ +\S+ {name=\S+ .*value=(\S+)}/ || # for xschem
           line =~ /F 1 \"([^\"]*)\"/ || # for eeschema
           line =~ /^ *[Mm]\S* +\([^\)]*\) +\S+ +(.*) */ || # for netlist
           line =~ /^ *[Mm]\S* +\S+ \S+ \S+ \S+ +\S+ +(.*) */ ||
           line =~ /^ *[VvIiCcRr]\S* +\S+ +\S+ +(.*) */
          substr = $1
          line.sub! substr, value
          elements[name][:value].sub!(substr, value)
        elsif line =~ /^C {(\S+).sym} +\S+ +\S+ +\S+ +\S+ {name=(\S+) +(.*)}/ # for xschem
          substr = $3
          value  
          if value[0] == '-'
            value = sub substr, value[1..-1]
          elsif value[0] == '+'
            value = add substr, value[1..-1]
          end
          line.sub! substr, value
          elements[name][:value].sub!(substr, value)
        end
        true
      else
        # puts "name=#{name} for file:#{file}"
        name =~ /(\S+)_(\d+)/ 
        elm = ($1 && elements[$1]) ? elements[$1][$2.to_i-1] : elements[name] && elements[name][0]
        if elm && lineno = elm[:lineno]
          line = lines[lineno-1]
          # puts line
          if line =~ /^C {code_shown.sym} +\S+ +\S+ +\S+ +\S+ {.* value=\"(\.(\S+) .*)\"/ || # for xschem
             line =~ /^ *([\.;]#{name}.*)$/ # for eeschema and netlist 
            substr = $1
            line.sub! substr, value
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
  
  def emulated_step_analysis step_desc = '.step param ccap 0.2p 1p 0.5p', node_list = ['frequency', 'V(out)/(V(net1)-V(net3))']
    steps = LTspice.new.step2params(step_desc)
    return nil if steps[0].nil?
    start, stop, step = steps[0]['values'].map{|v| eng2number(v)}
    results = [[], []]
    logs = with_stringio(){
      start.step(by: step, to: stop){|v|
        Ngspice.command "alterparam #{steps[0]['name']}=#{v}"
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

  def simulate *variables
    result = with_stringio{
      simulate0 variables
    }
    puts result
  end

  def simulate0 variables
    # system "unix2dos #{@file}" if on_WSL?() # NgspiceXVII saves asc file in LF, but -netlist option needs CRLF!
    file = nil
    netlist = ''
    analysis = {}
    steps = []
    $stderr.puts "@file = #{@file}"
    if @file =~ /\.asc/
      file = @file.sub('.asc', '.net')
      File.delete file if File.exist? file
      Dir.chdir(File.dirname @file){ # chdir or -netlist does not work 
        FileUtils.cp @file, @file.sub('.asc', '.tmp')
        run_ltspice '-netlist', File.basename(@file.sub('.asc', '.tmp'))
        wait_for File.basename(file), 'due to some error'
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
          File.delete file if file && File.exist?(file)
          run "-s -n -x -q -o .", @file # xschem options:
            # -s: set netlist type to spice
            # -n: create netlist
            # -i: do not load any xschemrc file
            # -x: command mode (no X)
            # -q: quit after doing things 
            # -o: output directory
          wait_for File.basename(file), 'due to some error'

          $stderr.puts "file='#{file}'"
          sleep 1 # weird but file is not available w/o sleep 1
          netlist = ''
          home = (ENV['HOMEPATH'] || ENV['HOME'])
          File.read(file.gsub(/\\/, '/')).each_line{|l|
            if l =~ /^ *\.step/
              steps = LTspice.new.step2params(l)
              netlist << '*' + l
              $stderr.puts "commented out: #{l}"
            else
              netlist << l.sub(/%HOMEPATH%|%HOME%|\$HOMEPATH|\$HOME/, home)
            end
          }
        }
      end
    elsif @file =~ /\.cir|\.net|\.spi|\.spice/ 
      netlist, steps = parse(@file, analysis, '^ *\.step')
      $stderr.puts "netlist = #{netlist}"
      $stderr.puts "analysis = #{analysis}"
    end
    @netlist = netlist
    $stderr.puts "analysis directives in netlist: #{analysis.inspect}" # unless analysis.empty?
    Dir.chdir(File.dirname @file){
      $stderr.puts "variables = #{variables.inspect}"
      Ngspice.init
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
      @@step_results[@file] = [[], []]
      node_list = variables[0] ? variables[0][:probes] : nil
      if steps[0] == nil || node_list == nil
        simulate_core analysis
      else
        start, stop, step = steps[0]['values'].map{|v| eng2number(v)}
        $stderr.puts "start step analysis with (#{start}, #{stop}, #{step})"
        #logs = with_stringio(){
          start.step(by: step, to: stop){|v|
            Ngspice.command "alterparam #{steps[0]['name']}=#{v}"
            Ngspice.command 'reset'
            Ngspice.command 'listing param'
            simulate_core analysis
            r = get_active_traces *node_list
            $stderr.puts "node_list = #{node_list}"
            $stderr.puts "r=#{r.inspect}"
            r[1][0][:name] = "#{steps[0]['name']}=#{v}" if r[1][0]
            @@step_results[@file][0] = r[0]
            @@step_results[@file][1] << r[1][0]
          }
        #}
        #$stderr.puts logs
      end
    }
    # @result = Ngspice.get_result
  end

  def simulate_core analysis
    if analysis.empty?
      Ngspice.command('run')
    else
      $stderr.puts "analysis = #{analysis.inspect}"
      analysis.each{|k, v|
        Ngspice.command "#{k} #{v.downcase}" # do not know why but must be lowercase
      }
    end    
  end

  def sim_log ckt=@file # should be revised!
    File.read(ckt.sub('.asc', '.log')).gsub("\x00", '')
  end
  
  def with_stringio
    require 'stringio'
    stdout_keep = $stdout
    $stdout = StringIO.new
    yield
    result = $stdout.string
    $stdout = stdout_keep
    result.dup
  end

  def info
    result = nil
    with_stringio(){
      Ngspice.info
    }.each_line{|l|
      if result && l =~ /stdout *(\S+) */
        result << $1
      elsif l =~ /stdout Date:/
        result = []
      end
    }
    result
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
  
  def node_list_to_variables node_list
    variables = [node_list[0]]
    node_list[1..-1].each{|a|
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
      if variables[0] == 'frequency'
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
    if @@step_results[@file] && @@step_results[@file][0].size > 0
      @@step_results[@file]
    else
      get_active_traces *node_list
    end
  end

  def get_active_traces *node_list
    # node_list_to_get_result = Marshal.load(Marshal.dump node_list)
    # $stderr.puts "node_list='#{node_list}' @ get_active_traces"
    return [[], []] if node_list.size == 0
    variables = node_list_to_variables node_list
    $stderr.puts "variables=#{variables} @ get_active_traces"
    @result = Ngspice.get_result variables[1..-1]
    # $stderr.puts @result
    indices = []
    vars = []
    traces = []
    # variables.delete 'v-sweep'
    # rc = true if variables[0] == 'frequency'
    variables.each_with_index{|name, i|
      if variables.include? name
        indices <<  i
        if variables[0] == 'frequency' && name =~ /real\((.*)\)/
            vars << $1
        else
          vars << name
        end
      end
    }
    old_index = index = -100000
    count = 0
    old_value = nil
    @result.map{|h| h.values}.each{|values|
      index = values[0].to_i
      values = values[1..-1]
      # puts "index: #{index} > old_index: #{old_index}"
      break if index < old_index
      indices[1..-1].each_with_index{|j, i|
        if variables[0] == 'frequency' 
          if i % 2 == 0
            if index == 0
              traces << {x: Array_with_interpolation.new, y: Array_with_interpolation.new, name: vars[i+1].gsub('"', '')}
            end
            traces[count+i/2][:x] << values[0]
            traces[count+i/2][:y] << Complex(values[j], values[j+1])
          end
        else
          if old_value.nil?  || old_value > values[0]
            count = traces.size
            traces << {x: Array_with_interpolation.new, y: Array_with_interpolation.new, name: vars[i+1].gsub('"', '')}
          end
          traces[count+i][:x] << values[0]
          traces[count+i][:y] << values[j]
        end
      }
      old_index = index
      old_value = values[0]
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
    elsec
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
  #file = File.join 'c:', ENV['HOMEPATH'], 'work/Op8_18/Xschem/op8_18_tb_direct_ac.sch'
  file = File.join 'c:', ENV['HOMEPATH'], 'work/Op8_18/Xschem/op8_18_tb_direct_ac.spice'
  #file = File.join 'c:', ENV['HOMEPATH'], 'work\Op8_18\Xschem\simulation\op8_18_tb_direct_ac.spice'
  #file = File.join 'c:', ENV['HOMEPATH'], 'Seafile/MinimalFab/work/SpiceModeling/Xschem/Idvd_nch_pch.spice'
  ckt = NgspiceControl.new file, true, true # test recursive
  #puts ckt.elements.inspect
  #puts ckt.models.inspect
  ckt.simulate probes: ['frequency', 'V(out)/(V(net1)-V(net3))']
  r = ckt.get_traces('frequency', 'V(out)/(V(net1)-V(net3))') # [1][0][:y]
  #r = ckt.get_traces('v-swe            ep', 'vds#branch')
  puts r[1][0][:y] if r[1] && r[1][0]
  ckt = NgspiceControl.new file, true, true # test recursive
  r = ckt.get_traces('frequency', 'V(out)/(V(net1)-V(net3))') # [1][0][:y]
  puts 'sim end'
end
