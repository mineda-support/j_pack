# ngspctl v0.3 Copyright(C) Anagix Corporation
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
require 'ngspctl'
require 'postprocess'
require 'compact_model'
load './customize.rb' if File.exist? './customize.rb'
require 'debug'
require 'fileutils'

class EEschemaControl < NgspiceControl
  attr_accessor :elements, :file, :mtime, :pid, :result, :sheet, :netlist, :step_results

  def initialize ckt=nil, ignore_cir=true, recursive=false
    return unless ckt
    @step_results = []
    @ckts = {}
    read ckt, ignore_cir, recursive
    get_models e=@elements[@file.sub(/\.\S+/, '')] || @elements 
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
    if file.class == Array
      file, work_dir = file
    else
      work_dir = File.dirname(file)
    end
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
    read0 ckt, recursive # @elements is set
    if ckt.class == Array
      ckt, work_dir = ckt
      @work_dir = work_dir
    end  
    @sheet = {ckt => @elements}
    read_subckt @elements['Sheets']
    cir = ckt.sub('.kicad_sch', '.cir')
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
    if ckt.class == Array
      @file, work_dir = ckt
    else
      @file = ckt
    end  
    case File.extname @file 
    when '.asc'
        @elements = read_asc @file, recursive
    when '.kicad_sch'
        @elements = read_sch @file, work_dir, recursive
    when '.net', '.spice', '.cir', '.spc'
        @elements = read_net @file
        @sheet && @sheet.each_key{|file|
          @sheet[file] = read_eeschema_sch file, work_dir, recursive
        }
    when ''
      if File.exist? @file+'.asc'
        @elements = read_asc @file+'.asc', recursive
      elsif File.exist? @file+'.kicad_sch'
        @elements = read_sch @file+'.kicad_sch', work_dir, recursive
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

  def read_sch file, work_dir, recursive=false, caller=''
    read_eeschema_sch file, recursive, caller
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

  def set pairs
    if @file =~ /\.asc/
      super pairs
    else
      if @sheet && !@sheet.empty?
        cir = @file.sub('.kicad_sch', '.cir')
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
      # e = @elements[File.basename(@file).sub(/\.\S+/, '')] || @elements
      e = @elements[@file.sub(/\.\S+/, '')] || @elements 
      lines, result = set0 pairs, file, e, @mtime
      update(file, lines) 
      result
    end
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
  #ckt = NgspiceControl.new file, true, true # test recursive
  file = File.join 'c:', ENV['HOMEPATH'], "Seafile/Citizen035/Op8_22/Citizen035/EEschema/op8_22_v2.kicad_sch"
  Dir.chdir(File.join 'c:', ENV['HOMEPATH'], 'Seafile/Citizen035/Op8_22/Citizen035/EEschema')
  ckt = EEschemaControl.new file, true, false # note: ckt.set (update) does not work with recursive=true
  puts ckt.elements.inspect
  #ckt.set({:VD=>"0.05"})
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
  ckt.simulate probes: ['time', 'v(clk)']
  r = ckt.get_traces 'time', 'v(clk)'
  puts 'sim end'
end
