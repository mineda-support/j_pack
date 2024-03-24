# coding: cp932
#require 'rubygems'
require 'sxp'
# require 'ruby-debug'
require 'fileutils'

class Array
  def edif_get key
    self[1..-1].find{|s| s[0] == key}
  end

  def edif_get_all key
    self[1..-1].select{|s| s[0] == key}
  end

  def edif_hash *k
    hash = {}
    k.each{|k2|
      if result = edif_hash2(k2)
        hash.merge! result
      end
    }
    hash
  end
  def edif_hash2 key, is_hash=true
    #    puts "#{key} for #{self.inspect}"
    if self[0] == key
      return (is_hash)? {key => self[1]} : self[1]
    else
      self[1..-1].each{|s|
        if s.class == Array
          result = s.edif_hash2 key, is_hash
          return result if result
        end
      }
    end
    nil
  end
  def edif_value key
    edif_hash2 key, nil
  end
  def edif_property key
    self[1..-1].each{|s|
      next unless s.class == Array
      if s[0] == :property && s[1] == key
        return s.edif_value :string || s.edif_value(:integer).to_int
      end
    }
    nil
  end
  def edif_direction
    d = self.edif_value(:direction)
    case d
    when :INPUT
      return 'in'
    when :OUTPUT
      return 'out'
    when :INOUT
      return 'inout'
    end
  end
end
class Edif_out
  attr_accessor :edifVersion, :edifLevel, :keywordMap, :status, :libraries , :comment
  def initialize s 
    @edifVersion, @edifLevel, @keywordMap, @status = s[2..5]
    @design = s[-1]
    @comments = []
    @libraries = []
    $rename_lib = {}
    $rename_cell = {} 
    s[6..-1].each{|c|
      puts "#{c[0]}: #{c[1]}"
      case c[0]
      when :comment
        @comments << c
      when :library
        @libraries << EdifLibrary.new(c)
      end
    }
  end
  def q2c str
    i=str.to_i
    #i*16/10
    i*16/10
  end
  def rename s
    if s[0] == :rename
      s[2]
    end
  end
  def IP62_pin_order s
    cell_name = (s.class == Array)? rename(s): s
    case cell_name
    when 'DN', 'DP'
      [1, 0]
    when 'RR_W2.8', 'RR', 'RN', 'RNHV', 'RS', 'RH', 'RHHV'
      [1, 2]
    when 'CSIO'
      [1, 0]
    else
      nil
    end
  end
  def edif2cdraw 
    @libraries.each{|l|
      puts "library #{l.name}"
      FileUtils.mkdir_p File.join('pictures', l.name)
      l.cells.each{|c|
        puts " cell #{c.name}"
        next if c.view.nil?     
        if c.view.interface
          #            c.view.interface.ports && c.view.interface.ports.each{|p|
          #              puts "port: #{p.name}"
          #            }
          if c.view.interface.symbol
            File.open(File.join('pictures', l.name, c.name+'.asy'), 'w'){|f|
              f.puts <<EOF
Version 4
SymbolType CELL
EOF
              c.view.interface.symbol.figures.each{|edif_figure|
                edif_figure.figures.each{|fig|
                  case fig[0]
                  when :path, :polygon
                    #f.puts "LINE Normal #{q2c(fig[1][0])} #{q2c(fig[1][1])} #{q2c(fig[2][0])} #{q2c(fig[2][1])}"
                    fig[1..-2].each_index{|i|
                      f.puts "LINE Normal #{q2c(fig[i+1][0])} #{q2c(fig[i+1][1])} #{q2c(fig[i+2][0])} #{q2c(fig[i+2][1])}"
                      f.puts "LINE Normal #{q2c(fig[1][0])} #{q2c(fig[1][1])} #{q2c(fig[i+2][0])} #{q2c(fig[i+2][1])}" if fig[0] == :polygon
                    }
                    when:circle
                    f.puts "CIRCLE Normal #{q2c(fig[1][0])} #{q2c(fig[1][1])} #{q2c(fig[2][0])} #{q2c(fig[2][1])}"
                  end
                }
              }
              c.view.interface.properties.each{|prop|
                if prop[0] == :instNamePrefix
                  f.puts "SYMATTR Prefix #{prop[1]}"
                end
              }
              f.puts "SYMATTR Value #{c.name}"
              c.view.interface.symbol.commentGraphics.each{|cg|
                x, y = cg.hash[:origin]
                if cg.hash[:stringDisplay] == 'cdsName()'
                  f.puts "WINDOW 0 #{x} #{y} Left 2"
                elsif cg.hash[:stringDisplay] == 'cdsParam(1)'
                  f.puts "WINDOW 2 #{x} #{y} Left 2"
                end
              }
              if pin_order = IP62_pin_order(c.name)
                (0..pin_order.size-1).each{|i|
                  pin = c.view.interface.symbol.pins[pin_order[i]]
                  f.puts "PIN #{q2c(pin.xy[0])} #{q2c(pin.xy[1])} NONE 0"
                  f.puts "PINATTR PinName #{pin.name}"
                  f.puts "PINATTR SpiceOrder #{i+1}"
                }                 
              else
                c.view.interface.symbol.pins.each_with_index{|pin, i|
                  f.puts "PIN #{q2c(pin.xy[0])} #{q2c(pin.xy[1])} NONE 0"
                  f.puts "PINATTR PinName #{pin.name}"
                  f.puts "PINATTR SpiceOrder #{i+1}"
                }
              end
            }
          end
        end
        if c.view.contents
          ref = {}
          puts "c.name=#{c.name}"
          File.open(File.join('pictures', l.name, c.name+'.asc'), 'w'){|f|
            f.puts <<EOF
Version 4
SHEET 1 7088 2000
EOF
            c.view.contents.pages.nets.each{|n|
              puts "  net #{n.name}"
              n.wires.each{|w|
                f.puts "WIRE #{q2c(w[0][0])} #{q2c(w[0][1])} #{q2c(w[1][0])} #{q2c(w[1][1])}"
              }
            }
            pi = c.view.contents.pages.port_implementations
            puts "pi=#{pi}"
            c.view.interface.ports.each_pair{|k, p|
              k, name = (k.class == Array) ? [k[1], k[2]] : [k, k]
              puts "pi[#{k}] =  #{pi[k]}"
              x = q2c(pi[k][:connectLocation][0])
              y = q2c(pi[k][:connectLocation][1])
              f.puts "FLAG #{x} #{y} #{name}"
              f.puts "IOPIN #{x} #{y} #{p[:direction]}"
            }
            c.view.contents.pages.instances.each{|i|
              puts "  instance '#{i.name}: #{i.cellRef}' in '#{i.libraryRef}'"
              ref[i.cellRef] = i.libraryRef
              puts "    #{i.orientation}, #{i.origin.inspect}"
              case i.orientation
              when :R90
                orient = "R270"
              when :R270
                orient = "R90"
              when :MY
                orient = "M0"
              when :MYR90
                orient = "M90"
              when :MX
                orient = "M180"
              when :MXR90
                orient = "M270"
              else
                orient = "R0"
              end
              f.puts "SYMBOL #{$rename_cell[i.cellRef]} #{q2c(i.origin[0])} #{q2c(i.origin[1])} #{orient}"
              f.puts "SYMATTR InstName #{i.name}"
              case prefix=i.name.to_s[0].downcase
              when 'm'
                f.print "SYMATTR Value2"
                i.properties.each_pair{|k, v|
                  f.print " #{k}=#{v}"
                }
                f.puts
              when 'c', 'r'
                i.properties.each_pair{|k, v|
                  if k.to_s.downcase == prefix
                    f.puts "SYMATTR Value #{v}"
                  end
                }
              end
            }
          }
          File.open(File.join('pictures', l.name, c.name+'.yaml'), 'w'){|f|
            f.puts "cells:"
            ref.each_pair{|c_ref, l_ref|
              f.puts "  #{$rename_cell[c_ref]}: #{$rename_lib[l_ref]}"
            }
          }
        end
      }
    }
  end
end
class EdifLibrary
  attr_accessor :name, :edifLevel, :technology, :cells
  def initialize s
    name, @edifLevel, @technology, *cells = s[1..-1]
    @cells = cells.map{|c| EdifCell.new c}
    @name = (name.class == Symbol)? name.to_s : name[2]
    if name.class == Symbol
      @name =  name.to_s
      $rename_lib[name] = @name
    else
      @name =  name[2]
      $rename_lib[name[1]] = @name
    end
  end
end
class EdifCell
  attr_accessor :name, :cellType, :view
  def initialize s
    name, @cellType, view = s[1..-1]
    @view = EdifView.new view
    if name.class == Symbol
      @name =  name.to_s
      $rename_cell[name] = @name
    else
      @name =  name[2]
      $rename_cell[name[1]] = @name
    end
  end
end
class EdifView
  attr_accessor :name, :viewType, :interface, :contents
  def initialize s
    @name, @viewType, interface, contents = s[1..-1]
    #    puts "View name = #{@name}"
    if @name == :symbol
      @interface = EdifSymbolInterface.new interface
    elsif @name == :schematic
      @interface = EdifSchematicInterface.new interface
      @contents = EdifContents.new contents if contents
    end
  end
end
class EdifSymbolInterface
  attr_accessor :ports, :symbol, :properties
  def initialize s
#    @ports = s[1..-2].map{|p| EdifPort.new p} if s.size > 1
    @ports = {}
    s[1..-1].each{|p|
      direction = nil
      
      @ports[p[1]] = {direction: p.edif_direction}
    }
#    puts "symbol: #{s[-1].inspect}"
    @symbol = EdifSymbol.new s[-1] if s.size > 2 && s[-1]
    @properties = {}
    s[1..-2].edif_get_all(:property).each{|c|
      @properties[c[1]] = c.edif_value :string || c.edif_value(:integer).to_int
    } if s.size > 2
  end
end
class EdifSchematicInterface
  attr_accessor :ports, :symbol
  def initialize s
    @ports = {}
    s[1..-1].each{|p|
      @ports[p[1]] = {direction: p.edif_direction} if p[0] == :port
    }
    # @ports = s[1..-1].map{|p| EdifPort.new p}
    @properties = s[1..-1].edif_get_all :property
    #    puts "symbol: #{s[-1].inspect}"
    if symbol = s.edif_get(:symbol)
      @symbol = EdifSymbol.new symbol
    end
  end
end
=begin
class EdifPort
  attr_accessor :name, :direction
  def initialize s
    @name = (s[1].class == Array)? rename(s[1]): s[1]
    @direction = s[2]
  end
  def rename s
    if s[0] == :rename
      s[2]
    end
  end
end
=end
class EdifSymbol
  attr_accessor :boundingBox, :commentGraphics, :figures, :properties
  attr_accessor :pins
  def initialize s
    bb =  EdifBoundingBox.new s.edif_get(:boundingBox)
    # puts "bb=#{bb} for s.edif_get(:boundingBox) = #{s.edif_get(:boundingBox)}"
    @boundingBox = bb.rectangle
    @commentGraphics = []
    s.edif_get_all(:commentGraphics).each{|cg|
      @commentGraphics << EdifCommentGraphics.new(cg)
    }
    @figures = []
    #    @portImplementations = []
    @pins = []
    @properties = {}
    s.edif_get_all(:figure).each{|c|
      @figures << EdifFigure.new(c)
    }
    s.edif_get_all(:portImplementation).each{|c|
      @pins << EdifPin.new(c)
    }
  end
end
class EdifPin
  attr_accessor :name, :xy 
=begin
     (portImplementation h01
      (connectLocation
       (figure pin
        (dot (pt 0 0))
       )
       (figure device
        (rectangle
         (pt -4 -4)
         (pt 4 4)
        )
       )
      )
      (property pin_name
       (string "h01")
       (property x (integer 0)(owner "SILVACO"))
       (property y (integer 0)(owner "SILVACO"))
       ...
      )
     )
=end  
  def initialize s # s:(portImplementation D (connectLocaion ...))
    @name = s.edif_property(:pin_name) || s[1]
    @xy = pt(s.edif_value(:dot))
  end
  def pt s
    [s[1], -s[2]]
  end
end
class EdifFigure
  attr_accessor :figures
  def initialize s
    @figures = []
    s[2..-1].each{|f|
      case f[0]
      when :circle
        @figures << [:circle, pt(f[1]), pt(f[2])]
      when :path, :polygon
        if f[1][0] == :pointList
          @figures << [f[0], *f[1][1..-1].map{|a| pt a}]
        end
      end
    }
  end
  def pt s
    [s[1], -s[2]]
  end
end
class EdifBoundingBox
  attr_accessor :rectangle 
=begin
     (boundingBox 
      (rectangle 
       (pt -6 -30)
       (pt 66 26)
      )
     )
=end
  def initialize s
    @rectangle = [pt(s[1][1]), pt(s[1][2])]
  end
  def pt s
    [s[1], -s[2]]
  end
end
class EdifCommentGraphics
  attr_accessor :hash
  Sample =    <<EOF
      (commentGraphics
       (annotate
        (stringDisplay "out"
         (display
          (figureGroupOverride annotate
           (textHeight 8)
          )
          (justify LOWERLEFT)
          (orientation R0)
          (origin (pt 46 -6))
         )
        )
       )
      )
EOF
  def initialize s
    return if s.nil?
    @hash = s.edif_hash :stringDisplay, :textHeight, :justify, :orientation
    if xy = s.edif_value(:origin)
      result = {:origin => pt(xy)}
      @hash.merge! result
    end
  end
  def pt s
    [s[1], -s[2]]
  end  
end
class EdifContents
  attr_accessor :pages
  def initialize s
    #    puts "page: #{s[1].inspect}"
    @pages = EdifPage.new s[1]
  end
end
class EdifPage
  attr_accessor :commentGraphics, :instances, :port_implementations, :nets
  def initialize s
    debugger if s.nil?
    #    @commentGraphics = s[-1]
    @instances = []
    @port_implementations = {}
    @nets = []
    @commentGraphics = []
    s[2..-1].each{|c|
      case c[0]
      when :instance
        @instances << EdifInstance.new(c)
      when :portImplementation
        pi = EdifPortImplementation.new(c)
        @port_implementations[c[1][1]] = pi.hash
      when :net
        @nets << EdifNet.new(c)
      when :commentGraphics
        @commentGraphics << c
      end
    }
  end
end
class EdifPortImplementation
  attr_accessor :hash
  def initialize s
    @hash = {}
    @hash[:name]= s.edif_value(:name)
    @hash[:justify] = s.edif_value(:justify)
    @hash[:orientation] = s.edif_value(:orientation)
    @hash[:origin] = pt(s.edif_value(:origin))
    @hash[:connectLocation] =pt(s.edif_get(:connectLocation).edif_value(:dot))
  end
  def pt s
    [s[1], -s[2]]
  end
end
class EdifInstance
  attr_accessor :name, :properties
  attr_accessor :cellRef, :libraryRef, :orientation, :origin
  def initialize s
    @name, viewRef, transform, *properties = s[1..-1]
    @cellRef = viewRef.edif_value :cellRef
    @libraryRef = viewRef.edif_value :libraryRef
    @orientation = transform.edif_value :orientation
    origin = transform.edif_value(:origin) 
    @origin = pt(origin) if origin
    @properties = {}
    properties.each{|p|
      case prefix=@name.to_s[0].downcase
      when 'm'
        next unless [:w, :l, :m].include? p[1]
      when 'c', 'r'
        next if p[1].to_s.downcase != prefix
      end
      case p[2][0]
      when :string
        @properties[p[1]]  = p[2][1].gsub(/%\d+%/){|w| w[1..-2].to_i.chr}
      when :integer
        @properties[p[1]]  = p[2][1].to_i
      end
    }
  end
  def pt s
    [s[1], -s[2]]
  end
end
class EdifNet
  attr_accessor :name, :wires
=begin
# silvaco
        (path
         (pointList
          (pt 1800 170)
          (pt 1980 170)
         )
         (property is_global (boolean (false))(owner "SILVACO"))
         (property is_implicit (boolean (false))(owner "SILVACO"))
         (property show_net_names_always (boolean (false))(owner "SILVACO"))
         (property has_sig_name (boolean (true))(owner "SILVACO"))
         (property netlistorder (integer 1)(owner "SILVACO"))
         (property text_size (integer 12)(owner "SILVACO"))
        )
# cadence
(net VOUT (joined
	 (portRef  VOUT)
	 (portRef  PLUS (instanceRef C2))
	 (portRef  D (instanceRef M36))
	 (portRef  D (instanceRef M42)))
       (criticality 0)
       (figure wire (path (pointList
	 (pt 2080 -480) (pt 2080 -380))))
       (figure wire (path (pointList
	 (pt 2010 -380) (pt 2080 -380))))
       (figure wire (path (pointList
	 (pt 2080 -380) (pt 2080 -250))))
       (figure wire (path (pointList
	 (pt 2080 -640) (pt 2080 -480))))
       (figure wire (path (pointList
	 (pt 2080 -480) (pt 2170 -480)))))
=end
  def initialize s
    @name, @joined, *rest = s[1..-1]
    @wires = []
    rest.each{|figure|
      if figure[0] == :figure
        if figure[2][0] == :path
          path = figure[2]
          @wires <<[pt(path[1][1]), pt(path[1][2])]
        end
      end
    }
  end
  def pt s
    [s[1], -s[2]]
  end
end
puts Dir.pwd

file = './j_pack/AMP_01_00_edif.out'
require 'sxp'
require 'debug'
desc = SXP.read(File.read(file).encode('UTF-8'))
e = Edif_out.new desc
e.edif2cdraw
