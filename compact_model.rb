class CompactModel
  attr_accessor :file, :models, :type
  require 'spice_parser'
  require 'alb_lib'
  @@models = {}

  def initialize file, name=nil
    @file = file
    @models = load file
    @current = @models.keys[0]
    @type = @models[@current][0]
    @model_params = @models[@current][1]
    @orig_params = @model_params.dup 
    @@models[file] = models
  end

  def self.models ()
    @@models
  end

  def current model = @current
    actual_model = actual(model, @models)
    @current = actual_model
    @type, @model_params = @models[@current]
    puts "current model: #{@current}"
    @current
  end

  def model_params model = @current
    type = @models[model][0]
    puts ".model #{model} #{type}"
    puts @models[model][1]
    @models[model][1]
  end

  def help
    puts "help:"
    puts " help --- show this message"
    puts " current [name] --- set/show current model"
    puts " model_params [name] --- show current/specified model parameters"
    puts " file --- show default file name"
    puts " type --- show current model type"
    puts " reset [name] --- reset to initial CompactModel(file) parameters"
    puts " update model_params[, file] --- modify model parameters in a file"
    puts " load file --- replace model parameters with loaded from file"
    puts " save [file] --- save model parameters in a file"
    puts " set parm1: value, param2: value ... --- change model parameters"
    puts " get param --- get model parameter value" 
    puts " show parm1, param2, ... --- show specified model parameters"
    puts " delete param --- delete model parameter and value"
  end

  def reset model=@current
    if model != @current
      @current = model
      @type, @model_params = @models[model]
    end
    @model_params = @orig_params.dup
  end

  def load file
    models = {}
    description = nil
    File.read(file).each_line{|l|
      if l =~ /\.(model|MODEL)/ 
        if description
          type, name, params = parse_model(description)
          models[name] = [type, params]
        end
        description = l
      else
        description << l
      end
    }
    type, name, params = parse_model(description)
    models[name] = [type, params]
    return models
  end

  def update model_params_temp = @model_params, file = @file
    description = ''
    model_params = {}
    model_params_temp.each_pair{|k, v|
      model_params[k.to_s] = v
    }
    model_found = nil 
    File.read(file).each_line{|l|
      if l.downcase =~ /\.model +(\S+)/
        if $1.downcase == @current.downcase
          model_found = true
        else
          model_found = nil
        end
      elsif model_found
        if l =~ /^ *\+ *(\S+)( *= *(\S+))/
          p=$1
          pattern = $2
          v=$3
          if model_params[p] && (model_params[p] != v)
            print l
            l.sub!(pattern, " = #{model_params[p]}")
            puts " ===> #{l}"
          end
        end
      end
      description << l
    }
    File.open(file, 'w'){|f|
      f.puts description
    }
  end

  def save_found f, model_found
    type, model_params = @models[model_found]
    f.puts ".MODEL #{model_found} #{type}"
    model_params.each_pair{|k, v|
      f.puts "+ #{k} = #{v}"
    }  
  end

  def save file = @file
    description = File.read file
    model_names = @models.keys.map{|m| m.downcase}
    File.open(file, 'w'){|f|
      model_found = nil
      description.each_line{|l|
        if l.downcase =~ /\.model +(\S+)/
          if model_names.include? $1.downcase
            model_found = $1
          elsif model_found
            save_found f, model_found
            model_found = nil
            f.puts l
          else
            f.puts l 
          end
        elsif model_found.nil?
          f.puts l
        end
      }
      if model_found
        save_found f, model_found
      end
    }
  end

  def set props
    actual_props = {}
    props.each_pair{|p, v|
      a = actual p
      @model_params[a] = v.to_s
      actual_props[a] = v
    }
    actual_props
  end

  def get param
    @model_params[actual param]
  end
  
  def actual p, params = @model_params
    params[s = p.to_s] and return s
    params[u = s.upcase] and return u
    params[l = s.downcase] and return l
    params[c = s.capitalize] and return c
    s
  end
  private :actual

  def show *params
    params.map{|param|
      get param
    }
  end

  def delete param
    @model_params.delete actual(param)
  end
end

=begin
def write_model model_params, file
  description = ''
  File.read(file).each_line{|l|
    if l =~ /^ *\+ *(\S+) *= *(\S+)/
      p=$1
      v=$2
      if model_params[p] != v
        print l
        l.sub!(/ *= *#{v}/, " = #{model_params[p]}")
        puts " ===> #{l}"
      end
    end
    description << l
  }
  File.open(file, 'w'){|f|
    f.puts description
  }
end
=end
