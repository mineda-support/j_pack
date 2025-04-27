['alta2', 'j_pack','j_pack/ade_express'].each{|f| a_path = File.join(ENV['HOMEPATH'], f)
  $:.unshift a_path if File.exist?(a_path) && !$:.include?(a_path)
}
$:.unshift '.' if File.exist?(".") && !$:.include?('.')
#exitload "j_pack.rb"

p "PWD = " + Dir.pwd

require 'csv'
require 'matrix'
require 'json'
require 'compact_model'

Q   = 1.6e-19   unless defined? Q-
ESi = 12        unless defined? ESi
Eox = 3.9       unless defined? Eox
E0  = 8.854e-12 unless defined? E0
T   = 300.0     unless defined? T
K   = 1.38e-23  unless defined? K
Ni  = 1.5e+10   unless defined? Ni
Vt  = K*T/Q     unless defined? Vt  


J_data = {"x" => [],"y" =>[],"z" =>[],"vgs"=> 0.0,"vds"=>0.0,"vbs" =>0.0,"vth" =>0.0,"l"=>0.0,"w"=>0.0,"gmax"=>[],"name" =>"","mode" =>"lines","meas"=>true} unless defined? J_data

J_table = [{"plot_number"=>0,"title"=>[],"title_x"=>[],"title_y"=>[],"day" => "","basename"=>"","filename"=>"","ver"=>0.99,"act"=>" ","device"=>"","dir"=>"","ext"=>"json","step"=>"","plotdata"=>[]},{"measdata"=>[],"plotdata"=>[]}] unless defined? J_table
J_vth_list = {"vds"=>[],"vbs" =>[],"vth" =>[],"l"=>[],"w"=>[],"memo" =>[]} unless defined? J_vth_list


class ModelFit
  attr_accessor :model, :model_org, :jtable
  def initialize model="models/test.lib", model_org="models/MinedaPTS06_TT",vth_lists='models/vth_test'
    @model     = CompactModel::new model
    @model_org = CompactModel::new model_org
    @vth_list  = read_vth vth_lists
    @jtable    = J_table.dup  
#    @jtable =  [{"plot_number"=>0,"title"=>[],"title_x"=>[],"title_y"=>[],"day" => "","basename"=>"","filename"=>"","ver"=>0.99,"act"=>" ","device"=>"","dir"=>"","ext"=>"","step"=>"","plotdata"=>[]},{"measdata"=>[],"plotdata"=>[]}] unless defined? J_table
  end

  # read csv file to table(like json type)
  def read_csv csv_file = './csv/test1.csv'
    table = CSV.table(csv_file).by_col!
  end
  #private :read_csv

  def read_measdata ctable, basename='json/vgid'
  #  p [ctable[0][39],ctable[1][39],ctable[2][39],ctable[3][39]]
    meas = []
    for j in 0..ctable.headers.size - 2 do 
      meas[j] = J_data.dup
      meas[j]["name"] =ctable.headers[j+1]
      meas[j]["x"]= [].dup
      meas[j]["y"]= [].dup
  #    p [j,ctable.size,meas[j]["name"]]
      for i in 0..ctable.size - 1 do
        meas[j]["x"][i] = ctable[0][i].round(5).dup
        meas[j]["y"][i] = ctable[j+1][i].dup
      end
    end
  #  p [meas[0]["x"][39],meas[0]["y"][39],meas[1]["y"][39],meas[2]["y"][39]]
    @jtable[1]["measdata"] = meas.dup
    @jtable[0]["basename"]= basename.dup
    @jtable[0]["act"] = "csv to json,"
    #@jtable
    true
  end

  # read json file to table
  def read_json json_file
    if !(FileTest.exist?(json_file)) then
      p json_file + "does not exist!!"
      return
    end
    File.open(json_file,mode = "r") do |f|
      table = JSON.load(f)
    end
  end

  private :read_json

  # read vth_list
  def read_vth vth_list = vth_lists
    if !(FileTest.exist?(vth_list)) then
      @vth_list = J_vth_list.dup
      File.open(vth_list, 'w') do |file|
        JSON.dump(@vth_list, file)
      end
    else
      File.open(vth_list,mode = "r") do |f|
        @vth_list = JSON.load(f)
      end
    end
  end

  private :read_vth
  
  ### write table to json_file
  def write_json table=@jtable
    data = table[0]
 
    dir  = data["dir"]
    name = data["basename"]
    ext  = data["ext"]
    if data["step"].empty? then
      step = "STEP0"
      data["step"] = step
    else
      step = [data["step"],"STEP0"].max
    end
    v_tmp = ver_check data
    data["ver"] = v_tmp
    ver  = (data["ver"]+0.01).round(3)
    if data["device"].empty? then
      device = ""
    else
      device = "_" + data["device"]
    end

    new_file = dir + name + "_" + step + device + ".ver" + ver.to_s + "." + ext
    data["filename"]=new_file
    data["day"] = Time.now.to_s
    data["ver"] = ver
    p "save file =" + new_file

    File.open(new_file, 'w') do |file|
      JSON.dump(table, file)
    end
  end

end

class Bsim3Fit < ModelFit

  def print_condition
    p "filename = " + @jtable[0]["filename"]
    meas =@jtable[1]["measdata"]
    datas =["name","vbs","vgs","vds","vth","l","w","mode"]
    datas.each{|a| 
      tmp =format("%-8s,",a)
      for i in 0..meas.size - 1 do
        if a == "vth" then
          tmp += format("%-8.4f,",meas[i][a].to_f)
        else
          tmp += format("%-8s,",meas[i][a].to_s)
        end
      end
      p tmp
    }
    true
  end

  def set_condition vgs:nil,vds:nil,vbs:nil,name:nil,l:nil,w:nil#,mode:nil
    meas =@jtable[1]["measdata"]
    ii = meas.size

    # 'name' set
    if name.nil? then
    elsif name.instance_of?(Array) then
      jj =name.size
      for i in 0..[ii,jj].min - 1 do
        meas[i]["name"] =name[i].to_s
      end
      strs ="name  "
      for i in 0..ii - 1 do
        strs += ( ", " + meas[i]["name"])
      end
      p strs
    else
      strs ="name  "
      for i in 0..ii - 1 do
        meas[i]["name"]=name
        strs += ( ", " + meas[i]["name"])
      end
      p strs
    end

    # 'vgs' set
    if vgs.nil? then
    elsif vgs.instance_of?(Array) then
      jj = vgs.size
      for i in 0..[ii,jj].min - 1 do
        meas[i]["vgs"] =vgs[i]
      end
      strs ="vgs   "
      for i in 0..ii - 1 do
        strs += ( ", " + meas[i]["vgs"].to_s)
      end
      p strs
    else
      for i in 0..ii - 1 do
      strs ="vgs   "
        meas[i]["vgs"]=vgs
        strs += ( ", " + meas[i]["vgs"].to_s)
      end
      p strs
    end

    # 'vds' set
    if vds.nil? then
    elsif vds.instance_of?(Array) then
      jj = vds.size
      for i in 0..[ii,jj].min - 1 do
        meas[i]["vds"] =vds[i]
      end
      strs ="vds   "
      for i in 0..ii - 1 do
        strs += ( ", " + meas[i]["vds"].to_s)
      end
    else
      strs ="vds   "
      for i in 0..ii - 1 do
        meas[i]["vds"]=vds
        strs += ( ", " + meas[i]["vds"].to_s)
      end
      p strs
    end

    # 'vbs' set
    if vbs.nil? then
    elsif vbs.instance_of?(Array) then
      jj = vbs.size
      for i in 0..[ii,jj].min - 1 do
        meas[i]["vbs"] =vbs[i]
      end
      strs ="vbs   "
      for i in 0..ii - 1 do
        strs += ( ", " + meas[i]["vbs"].to_s)
      end
      p strs
    else
      strs ="vbs   "
      for i in 0..ii - 1 do
        meas[i]["vbs"]=vbs
        strs += ( ", " + meas[i]["vbs"].to_s)
      end
      p strs
    end

    # 'l' set
    if l.nil? then
    elsif l.instance_of?(Array) then
      jj = l.size
      for i in 0..[ii,jj].min - 1 do
        meas[i]["l"] =l[i]
      end
      strs ="l     "
      for i in 0..ii - 1 do
        strs += ( ", " + meas[i]["l"].to_s)
      end
      p strs
    else
      strs ="l     "
      for i in 0..ii - 1 do
        meas[i]["l"]=l
        strs += ( ", " + meas[i]["l"].to_s)
      end
      p strs
    end

    # 'w' set
    if w.nil? then
    elsif l.instance_of?(Array) then
      jj = w.size
      for i in 0..[ii,jj].min - 1 do
        meas[i]["w"] =w[i]
      end
      strs ="w      "
      for i in 0..ii - 1 do
        strs += ( ", " + meas[i]["w"].to_s)
      end
      p strs
    else
      strs ="w     "
      for i in 0..ii - 1 do
        meas[i]["w"]=w
        strs += ( ", " + meas[i]["w"].to_s)
      end
      p strs
    end
   # print_condition
   # "finished!"
  end

  #### Duplicate jtable and data ####
  
  #### (1) "measdata" duplication #####
  def duplicate_data from = "measdata"
    data  = @jtable[1][from].dup
   # p data.size
    ddata = []
    d_list = data[0].keys
    for i in 0..data.size - 1 do
      ddata[i] = J_data.dup
      d_list.each {|x|
        ddata[i][x] = data[i][x].dup
      }
    end
    ddata
  end

  #### (1.5) Hash duplication #####
  def duplicate_hash from 
    data  = from.dup
    # p data.size
    ddata = []
    d_list = data[0].keys
    for i in 0..data.size - 1 do
      ddata[i] = J_data.dup
      d_list.each {|x|
      ddata[i][x] = data[i][x].dup
      }
    end 
    ddata
  end

  ### (2) duplicate @jtable[0]  ###
  def duplicate_head
    head = @jtable[0].dup

    dist=J_table.dup
    dhead = dist[0].dup
    dhead["day"]       = head["day"].dup 
    dhead["basename"]  = head["basename"].dup 
    dhead["filename"]  = head["filename"].dup 
    dhead["ver"]       = head["ver"].dup 
    dhead["act"]       = head["act"].dup 
    dhead["device"]    = head["device"].dup 
    dhead["dir"]       = head["dir"].dup 
    dhead["ext"]       = head["ext"].dup 
    dhead["step"]      = head["step"].dup
    dhead
  end

  ### (3) duplicate jtable ####
  def duplicate_jtable data: "measdata"
    qtable =J_table.dup
    qtable[0] = duplicate_head
    qtable[1]["measdata"] = duplicate_data(data)
    return qtable
  end

  #### data change by step ####
  def change_step datas: @jtable[1]["measdata"],step: 0.2
    data_c = []
    if step == 0 then
      return datas
    else
      for j in 0..datas.size - 1 do
        data_c << datas[j].dup
        data_c[j]["x"]=[]
        data_c[j]["y"]=[]
        data_c[j]["z"]=[]
        for i in 0..datas[j]["x"].size - 1 do
          xxx = datas[j]["x"][i]
          if (xxx.modulo(step).round(2)== 0 || xxx.modulo(step).round(2)== step ) then
            data_c[j]["x"] << datas[j]["x"][i].round(2)
            data_c[j]["y"] << datas[j]["y"][i]
            if datas[j]["z"].nil? != true then
              data_c[j]["z"] << datas[j]["z"][i]
            end
          end
        end
      end
      return data_c
    end
  end

  ### y-data and z-data change ####
  def exchange_y_z name = "measdata"
    data = @jtable[1][name]
    d_size =data.size
    for i in 0..d_size - 1 do
      mm = data[i]
      ancher = mm["y"].dup
      mm["y"] = []
      mm["y"] = mm["z"].dup
      mm["z"] = []
      mm["z"] = ancher.dup
    end
  end

  ### file version check  ###
  def ver_check head = @jtable[0] 

    sdata =[]
    if head["step"].empty? then
      step = ""
    else
      step = "_"+head["step"]
    end
    if head["device"].empty? then
      gname = head["basename"] + step
    else
      gname = head["basename"] + step + "_"+head["device"]
    end

    ["json/"].each { |dir|
      sdata = Dir.glob(dir + gname +".ver*.json")
    }

    if sdata.empty? then
      ver=0.99
    else
      ver =sdata.max.slice(/[0-9]\.[0-9]+/).to_f
    end
    head["ver"] = ver
    return ver
  end

  ###### graph operation methods ######
  
  ### (1) list graphs    #####
  def list_graph
    @jtable[1].keys
  end
  

  ### (2) Check graph exist ###
  def exist_graph target = "measdata"
    @jtable[1].key?(target)
  end
    
  ### (3) graph copy from souce to dist
  def copy_graph source= "measdata",dist = "meas_org",force = false 
    if (source == dist) then
      p "source and dist graphs are same!!"
      return false
    end
    if (exist_graph(dist) == false) then
      #p "['" + dist + "'] is not exist. create ['"+ dist + "']"
    elsif force == false then
      if dist == "measdata" then
        p "['" + dist + "'] is protected. Use copy_graph source,dist,[true]"
        return false
      end
    end

    @jtable[1][dist] = duplicate_data @jtable[1][source]
    p list_graph
    true
  end

  #### (4) graph Move from source to dist
  def move_graph source = "measdata",dist = "meas_org",force = false
    if copy_graph(source,dist,force) then
      if source != "measdata" then
        delete_graph source
        list_graph
        return true
      else
        p "graph['measdata'] dose not delelete"
        return false
      end
    else
      p "move is not successed !"
      list_graph
      return false
    end
  end
      
  #### (5) graph delete  ######
  def delete_graph dist = "test"
    if (exist_graph(dist) == false) then
      p "['" + dist + "'] is not exist."
      return false
    end

    @jtable[1].delete(dist)
    p list_graph
    return true
  end
  
  #### (6) graph add source <= target
  def add_graph source: "measdata",target: "measdata",dist: "test"
    ss = duplicate_data(source)
    tt = duplicate_data(target)
    i_ss = ss.size
    i_tt = tt.size

    for i in 0..i_tt -1
      ss[i+i_ss] = tt[i].dup
    end

    @jtable[1][dist] = ss
    list_graph
  end
    
  ### Storage calc data ("gmdata","simpledata","vthdata#)
  def plot_graph gname = "measdata"
    target = list_graph
    if @jtable[1].key?(gname) != true  then
      p gname +" is not exist " + target.to_s
      return false
    end
    ptable = J_table.dup
    ptable[0]             = duplicate_head
    ptable[1]["measdata"] = [].dup
    ptable[1]["plotdata"] = [].dup
    pdata                 = duplicate_data(gname)
    for i in 0..pdata.size - 1 do
      if pdata[i]["meas"] then
        ptable[1]["measdata"] << pdata[i]
      else
        ptable[1]["plotdata"] << pdata[i]
      end
    end

    if ptable[1]["measdata"].empty? then
      p "'measdata' is not exists"
      return false
    end
    
    if ptable[1]["plotdata"].empty? then
      p "'plotdata' is not exists"
      return false
    end

    ### ver search ###
    ptable[0]["act"]    = gname + " data,"
    ptable[0]["device"] = gname
    ver = ver_check(ptable[0])
    ptable[0]["ver"] = ver

    write_json ptable
    p "data:[" + gname + "] is saved!!"
    true
  end

  ### plot all Graphs except "plotdata"
  def plot_all_graphs
    graphs = list_graph #@jtable[1].keys
    graphs.delete("plotdata")
    graphs.each{|graph| 
      p graph
      plot_graph(graph)
    }
    #    p graphs
    true
  end

  ###### end of graph operation methods ######
  
  # [STEP0] Read amd Convert data from "plotdata" to "measdata" and save file.converted.json
  def imitate_measdata json_file
    @jtable[1] = (read_json json_file)[1].dup
    @jtable[0] = J_table[0].dup
    
    if @jtable[1]["plotdata"] != [] then 
      p "['plotdata'] moves ['measdata']"
      @jtable[1]["measdata"] = duplicate_data("plotdata") 
      @jtable[1]["plotdata"] = [].dup
      meas = @jtable[1]["measdata"]
      for i in 0..meas.size - 1 do
        for j in 0..meas[0]["x"].size - 1 do
          meas[i]["x"][j] = meas[i]["x"][j].round(7).dup #significant digit = 6
        end
      end
      
      fname = json_file.split("/").last
      ext   = fname.split(".").last
      @jtable[0]["dir"]      = json_file.split(fname)[0]
      @jtable[0]["basename"] = fname.split(ext)[0].split(".")[0]
      @jtable[0]["device"]   = ""
      @jtable[0]["act"] = "plot=>meas ,"
      @jtable[0]["ver"] = 0.99

      write_json @jtable
    else
      "no changed!"
    end
  end

  ### [STEP0] Calculate Vth from Id-Vgs curve [STEP1],[STEP2],[STEP3],[STEP4],[STEP6]
  def calculate_vth_vbs_relation flg: false, vgs: 0.0, vds: 0.05, vbs: [0.0, -0.5 , -1.0, -1.5,-2.0], lw: [[30e-6,30e-6]], mode: "lines",name: ["vbs=0.0","vbs=-0.5","vbs=-1.0","vbs=-1.5","vbs=-2.0"]
    
    meas = @jtable[1]["measdata"]

    for i in 0..meas.size - 1 do

      if name.instance_of?(Array) then
        if name.size == 1 then
          meas[i]["name"] = name[0]
        else
          meas[i]["name"] = name[i].dup
        end
      else
        meas[i]["name"] = name
      end
        

      if vbs.instance_of?(Array) then
        if vbs.size == 1 then
          meas[i]["vbs"] = vbs[0]
        else
          meas[i]["vbs"] = vbs[i]
        end
      else
        meas[i]["vbs"] = vbs
      end
      
      if vds.instance_of?(Array) then
        if vds.size == 1 then
          meas[i]["vds"] = vds[0]
        else
          meas[i]["vds"] = vds[i]
        end
      else
        meas[i]["vds"] = vds
      end
      
      if vgs.instance_of?(Array) then
        if vgs.size == 1 then
          meas[i]["vgs"] = vgs[0]
        else
          meas[i]["vgs"] = vgs[i]
        end
      else
        meas[i]["vgs"] = vgs
      end

      if lw.size == 1 then
        meas[i]["l"] =lw[0][0]
        meas[i]["w"] =lw[0][1]
      else
        meas[i]["l"] =lw[i][0]
        meas[i]["w"] =lw[i][1]
      end
            
      meas[i]["z"]    = []
      meas[i]["meas"] = true

      
      for j in 0..meas[i]["x"].size - 1 do
        meas[i]["x"][j] = meas[i]["x"][j].round(5) 
        if flg then
          meas[i]["x"][j] += meas[i]["vbs"]
        end

        if j < 1 then
          meas[i]["z"][0] = 0.0
        else
          meas[i]["z"][j] = (meas[i]["y"][j] - meas[i]["y"][j-1]) / (meas[i]["x"][j] - meas[i]["x"][j-1])
        end
      end
      ii  = meas[i]["z"].index(meas[i]["z"].max)
      vgm = meas[i]["x"][ii]
      idm = meas[i]["y"][ii]
      gmm = meas[i]["z"][ii]

      meas[i]["gmax"]= [vgm,idm,gmm]
      meas[i]["vth"] = ((gmm * vgm - idm)/gmm -vds/2.0).round(5)
      #meas[i]["name"] = "vbs= " + meas[i]["vbs"].to_s
    end

    @jtable[0]["act"] += "cal [vth,gm],"
    @jtable[0]["step"] = "STEP1"
    @jtable[0]["device"] = ""

    write_json @jtable
  end



  ###[STEP1]Define Vth Parameter (VTH0,K1,K2) Sub ###
  def convert_vth na: 6e+16

    phis = 2.0*Vt*Math.log(na / Ni)
    meas = {"x"=>[] , "y"=>[],"z"=>[],"name" =>""}
    for i in 0..@jtable[1]["measdata"].size - 1 do
      vbs = @jtable[1]["measdata"][i]["vbs"]
      meas["x"][i] = vbs
      meas["y"][i] = @jtable[1]["measdata"][i]["vth"].round(5)
      meas["z"][i] = Math.sqrt(phis - vbs) 
    end
    meas["name"] = "measured"
      meas
  end
  private :convert_vth
    
  ###[STEP1] Extract Vth Parameter [VTH0,K1,K2] main ###
  def step1_estimate_vth_k1_k2  #, model=@model,model_org=@model_org
    if (@model.get :NSUB).nil? then
      na = 6e+16
    else
      na = (@model.get :NSUB).to_f
    end
    vth = convert_vth(na: na)
    
    @jtable[0]["act"] +="determine VTHs "

     # meas = {"x"=>[] , "y"=>[],"z"=>[],"vds"=>0.0,"name" =>""}

    x = vth["z"]
    y = vth["y"]
    z = determine_2nd x ,y

    phis = 2.0*Vt*Math.log(na/Ni)
    phiss = Math.sqrt(phis)

    k2   = z[0]
    k1   = z[1]
    vth0 = (z[2] + z[1]* phiss - z[0]*phis).round(5) #k2 * Math.sqrt(phi)

    @model.set :VTH0 => vth0.round(5)
    @model.set :K1   => k1.round(5)
    @model.set :K2   => k2.round(5)
    @model.save

    a = "VTH0 =" + (@model.get :VTH0)
    b = " K1 = "  + (@model.get :K1)
    c = " K2 = "  + (@model.get :K2)
    puts " model file \("+  @model.file + "\) is saved " + a +b + c 

    a = "VTH0 =" + (@model_org.get :VTH0)
    b = " K1 = "  + (@model_org.get :K1)
    c = " K2 = "  + (@model_org.get :K2)
    puts " model file \("+  @model_org.file + "\) is saved " + a +b + c 
    
    true
  end


  ### [STEP1]  Delta-Vth Calculation ###
  def calc_vth_delta model=@model,vbs: 0.0,vds: 0.05,l: 30e-6,w:30e-6
    #model parameters
    if (model.get:NSUB).empty? then
     nsub   =  6.0E16
    else
      nsub   =  (model.get:NSUB).to_f
    end
    nch    =  (model.get:NCH).to_f
    tox    =  (model.get:TOX).to_f 
    lint   =  (model.get:LINT).to_f 
    wint   =  (model.get:WINT).to_f 
    leff   =  l - 2.0 * lint
    weff   =  w + 2.0 * wint
    nds    =  1.0e20

    nlx    =  (model.get:NLX).to_f
    k1     =  (model.get:K1).to_f
    k2     =  (model.get:K2).to_f
    k3     =  (model.get:K3).to_f
    k3b    =  (model.get:K3B).to_f
    w0     =  (model.get:W0).to_f
    dvt0   =  (model.get:DVT0).to_f
    dvt1   =  (model.get:DVT1).to_f
    dvt2   =  (model.get:DVT2).to_f
    dsub   =  (model.get:DSUB).to_f
    eta0   =  (model.get:ETA0).to_f
    etab   =  (model.get:ETAB).to_f
    dvt0w  =  (model.get:DVT0W).to_f
    dvt1w  =  (model.get:DVT1W).to_f
    dvt2w  =  (model.get:DVT2W).to_f
   
    # parameters
    phis  = 2.0*Vt*Math.log(nsub/Ni)
    phiss = Math.sqrt(phis)
    vbi   = K*T/Q * Math.log(nch * nds/(Ni**2))
    xdep  = Math.sqrt(2.0 * ESi * E0 * (phis - vbs)/(Q * nch))
    xdep0 = Math.sqrt(2.0 * ESi * E0 * phis/(Q * nch))    
    lt    = Math.sqrt(ESi * E0 * xdep/(E0 / tox)) * (1.0 + dvt2 * vbs)
    lt0   = Math.sqrt(ESi * E0 * xdep/(E0 / tox))
    ltw   = Math.sqrt(ESi * E0 * xdep/(E0 / tox)) * (1.0 + dvt2w * vbs)

    # delta function
    delta10  = k1 * Math.sqrt(1.0 + nlx/leff - 1.0)
    delta11  =( k3 + k3b * vbs) * tox/(weff + w0) * phis
    delta20  = - dvt0 * (Math.exp(-dvt1 * leff / (2.0 * lt)) + 2.0 * Math.exp(- dvt1 * leff / lt))*(vbi - phis)
    delta30  = - (Math.exp(-dsub * leff / (2.0 * lt0)) + 2.0 * Math.exp(- dsub * leff / lt0))*(eta0 + etab *vbs)
    delta40  = dvt0w * (Math.exp(-dvt1w * (weff * leff)  / (2.0 * ltw)) + 2.0 * Math.exp(- dvt1w * (weff * leff) / ltw))*(vbi - phis)
    #output
    p "delta10 ="  + format("%4.4f",delta10)
    p "delta11 ="  + format("%4.4f",delta11)
    p "delta20 ="  + format("%4.4f",delta20)
    p "delta30 ="  + format("%4.4f",delta30)
    p "delta40 ="  + format("%4.4f",delta40)
    delta =delta10 + delta11 + delta20 + delta30 + delta40
    p "delta   ="  + format("%4.4f",delta)
    p "dvt0=%{dvt0},dvt1=%{dvt1},eta0=%{eta0},etab=%{etab},lt=%{lt},lt0=%{lt0},phis=%{phis},vbi=%{vbi},dvthl1=%{delta20},dvthl2=%{delta30}"
    return {"dvt0"=>dvt0,"dvt1"=>dvt1,"eta0"=>eta0,"etab"=>etab,"lt"=>lt,"lt0"=>lt0,"phis"=>phis,"vbi"=>vbi,"dvthl1"=>delta20,"dvthl2"=>delta30}
  end

  ### [STEP1] Some Graphs Caliculation  #####

  ### (1) Graph "simpledata" calcuation  #####
  ### calculate Id-Vg Curve using Simple model (Gm-Scale Create)
  def step1_calc_simplemodel 
    table = @jtable[1]["measdata"]
    gm = []
    for j in 0..table.size - 1 do
      gm << J_data.dup
      gm[j]["x"] = []
      gm[j]["y"] = []
      gm[j]["z"] = []
      vgm  = table[j]["gmax"][0].dup
      idm  = table[j]["gmax"][1].dup
      gmm  = table[j]["gmax"][2].dup
      vds  = table[j]["vds"].dup
      vths = table[j]["vth"].dup
      vbs  = table[j]["vbs"].dup

      deltax = 2.0
      delta = 0.01
      gm[j]["x"][0] = vths
      gm[j]["y"][0] = 0
      gm[j]["x"][1] = vths + vds/2.0
      gm[j]["y"][1] = 0
      gm[j]["x"][2] = vths + vds/2.0 + delta 
      gm[j]["y"][2] = gmm * delta
      gm[j]["x"][3] = vgm 
      gm[j]["y"][3] = idm
      gm[j]["x"][4] = vgm + deltax
      gm[j]["y"][4] = idm + gmm * deltax  
      gm[j]["z"][0] = 0.0
      gm[j]["z"][1] = 0.0
      gm[j]["z"][2] = gmm
      gm[j]["z"][3] = gmm
      gm[j]["z"][4] = gmm
      
      gm[j]["name"] = "vbs= " + vbs.to_s
    end

    if @jtable[1]["simpledata"].nil? then
      p " dataset 'simpledata' create"
    end

    @jtable[1]["simpledata"]=gm.dup
    
    return list_graph
  end

  ### (2) Graph "gmdata" calcuation (Needs "simpledata")  #####
  def step1_calc_gmdata step: 0.1

    gmdata = change_step(step: step)

    for i in 0..gmdata.size - 1 do
      gmdata[i]["y"]    = gmdata[i]["z"].dup
      gmdata[i]["z"]    = []
      gmdata[i]["meas"] = true
    end
    
    if @jtable[1]["gmdata"].nil? then
      p " Graph 'gmdata' create"
    end

    if @jtable[1]["simpledata"].nil? == false then
      simple = @jtable[1]["simpledata"]
      jj = gmdata.size 
      ii = simple.size - 1
      for i in 0..ii do
        gmdata[jj+i] = J_data.dup
        gmdata[jj+i]["x"]    = simple[i]["x"].dup
        gmdata[jj+i]["y"]    = simple[i]["z"].dup
        gmdata[jj+i]["name"] = simple[i]["name"].dup
        gmdata[jj+i]["meas"] = false
      end
    else
      p "after step1_calc_simple_model,use step1_calc_gmdata"
    end
      
    @jtable[1]["gmdata"]=gmdata.dup
    return list_graph
  end

  #### (3) Id_Vgs Curves calculate and store in "idvgdata"
  def step1_calc_id_vgs step: 0.1
    idvgs     = []
    from_data = change_step(step: step)
    for i in 0..from_data.size - 1 do
      idvgs[i]         = from_data[i].dup
      idvgs[i]["meas"] = true
    end
    ii =idvgs.size - 1
    
    from_data =@jtable[1]["simpledata"]
    for i in 0..from_data.size - 1 do
      idvgs[i+ii]         = from_data[i].dup
      idvgs[i+ii]["meas"] = false
    end

    if @jtable[1]["idvgsdata"].nil? then
      p " Graph 'idvgsdata' create"
    end
    
    @jtable[1]["idvgsdata"] = idvgs.dup

    return list_graph
  end

  
  #### (4) Vth-Vbg curve calculation ######
  def step1_calc_vth_vbs
    if (@model.get :NSUB).nil? then
      na = 6e+16
    else
      na = (@model.get :NSUB).to_f
    end
    phis = 2.0*Vt*Math.log(na / Ni)
    phiss = Math.sqrt(phis)
    
    vth0 = (@model.get :VTH0).to_f
    k1   = (@model.get :K1).to_f
    k2   = (@model.get :K2).to_f
    
    vth0_org = (@model_org.get :VTH0).to_f
    k1_org   = (@model_org.get :K1).to_f
    k2_org   = (@model_org.get :K2).to_f
    
    meas1 =[0..2]
    for i in 0..2 do
      meas1[i] = J_data.dup
    end
    x1 = [] 
    vth =convert_vth(na: na) ##vth mesurement
    meas1[0]["x"] = vth["x"].dup
    meas1[0]["y"] = vth["y"].dup
    meas1[0]["name"] = "meas."
    meas1[0]["meas"] = true
    y1 =[]
    y2 =[]
    #for i in 0..6 do
    for i in 0..4 do
      x = - i * 0.5
      x1[i] = x
      y = Math.sqrt(phis - x)
      y1[i] = (k2 * y*y + k1 * y + vth0 -k1 * phiss + k2 * phis).round(5).dup
      y2[i] = (k2_org * y*y + k1_org * y + vth0_org -k1_org * phiss + k2_org * phis).round(5).dup
    end
    meas1[1]["x"]    = x1.dup
    meas1[1]["y"]    = y1.dup
    meas1[2]["x"]    = x1.dup
    meas1[2]["y"]    = y2.dup
    meas1[1]["name"] = "extracted"
    meas1[2]["name"] = "PTS06"
    meas1[1]["meas"] = false
    meas1[2]["meas"] = false
    d_from = @jtable[1]["measdata"][0]

    for i in 0..2 do
      meas1[i]["vgs"]  = d_from["vgs"].dup
      meas1[i]["vds"]  = d_from["vds"].dup
      meas1[i]["vgs"]  = d_from["vgs"].dup
      meas1[i]["l"]    = d_from["l"].dup
      meas1[i]["w"]    = d_from["w"].dup
      meas1[i]["mode"] = d_from["mode"].dup
    end

    if @jtable[1]["vthdata"].nil? then
      p " Graph 'vthdata' create"
    end
    @jtable[1]["vthdata"] = meas1.dup
    
    return list_graph
  end
    

  ### calculate some Guraphs and store Bsim3Fit  ######
  def step1_calc_graphs step: 0.1
    step1_calc_simplemodel
    #Id-Vgs  Graph using SimpleModel Calculates and stores in "simpledata"
    step1_calc_gmdata step: step
    #Gm-Vgs  Graph Calculates and stores in "gmdata"     
    step1_calc_id_vgs step: step
    #Id-vgs Graphs using measure ad simpleModel Calulate and in "idvgdata"
    step1_calc_vth_vbs
    #Vth-Vbs Graph Calculates and stores in "vthdata"
  end

  ### plot [STEP1] Graphs ["gmdata","idvgsdata","vthdata"]
  def step1_plot_graphs
    g_list = ["gmdata","idvgsdata","vthdata"]
    g_list.each{|g| plot_graph g}
  end
  
  ### [STEP2] Mobility Estimation Ueff[U0,UA,UB,UC]
  ###           Analysis in [STEP2] is performed using the same data as in [STEP1]
  ### [STEP2-1] step2_calculate_ueff_vgs_relationw mag: 1.0
  ###                    Ueff-Vgs Curve ["measdata"][i]["y"]:: Id => ueff  
  ### [STEP2-2] estimation ueff from ueff curve
  
  ### [STEP2-1] Calc. Ueff-Vgs Curve ["measdata"][i]["y"]:: Id => ueff  
  def step2_calculate_ueff_vgs_relation mag: 1.5, vgmf: false
    
    tox  = (@model.get :TOX).to_f
    cox = Eox*E0/tox
    
    ### change ["measdata"][i]["z"] ####
    id = duplicate_data "measdata" 
    
    @jtable[0]["act"] += "Set Ueff,"
    
    for i in 0..id.size - 1 do
      l    = id[i]["l"].dup
      w    = id[i]["w"].dup
      vth  = id[i]["vth"].dup
      vds  = id[i]["vds"].dup
      vgm  = id[i]["gmax"][0].dup
      if vgmf then
        ii   = id[i]["x"].index{|v| v>=vgm*mag}
      else
        ii   = id[i]["x"].index{|v| v>=vth*mag}
      end
      
      ik   = id[i]["x"].size - 1
      
      idm =id[i].dup
      id[i]["x"] = []
      id[i]["y"] = []
      id[i]["z"] = []
      
      for j in ii..ik do
        x = idm["x"][j]
        tmp = (x - vth - vds/2.0)
        id[i]["x"] << idm["x"][j].dup
        id[i]["y"] << (idm["y"][j]/tmp/cox/w*l/vds).dup
        id[i]["z"] << idm["z"][j].dup
      end
    end 

    return id
  end

  # [STEP2-2] estimation ueff from ueff curve
  def step2_estimation_u0_ua_ub_uc err: 1e-5,mag: 3.0

    tox  =(model.get :TOX).to_f
  
    @jtable[0]["step"] = "STEP3" 
    tag = 1.0
    magx = 2.0
    while(tag >= err && magx <= mag)  do 
      xy = (step2_calculate_ueff_vgs_relation mag: magx).dup
      a = xy[0].dup
      b = xy[0].dup
      b["y"] = []

      u0ss = []
      uass = []
      ubss = []
      vbss = []
      
      #calc dtermine_2nd
      for j in 0..xy.size - 1 do
        xd = []
        yd = []
        vth = xy[j]["vth"].dup
        vbss << xy[j]["vbs"].dup
        for i in 0..xy[j]["x"].size - 1 do
          xd << (xy[j]["x"][i] + vth).dup
          yd << (1.0/xy[j]["y"][i].abs).dup
        end
        zzz = determine_2nd xd,yd
        u0 = 1.0/zzz[2]
        ua = zzz[1]*u0*tox
        ub = zzz[0]*u0*tox**2
     
        u0ss << u0
        uass << ua
        ubss << ub
      end

      vth = b["vth"].dup
      vbs = b["vbs"].dup
      jj  = b["x"].size
      aa  = []
      bb  = []

      for j in 0..jj - 1 do
        dx = (b["x"][j] + vth)/tox
        b["y"][j] = u0/(1 + (ua ) * dx + ub * dx**2)
      end
      aa[0] = xy[0].dup
      bb[0] = b.dup
      tag = calc_stdv bb,aa
      magx += 0.01
    end
    p "cal. error #{((tag * 100).round(12))}% @ mag= #{(magx - 0.01).round(4)}"
     # average & std
    ii = u0ss.size
    avgs = (u0ss.sum / ii)
    stds = (u0ss.map{|x| ((x - avgs)/avgs)**2}.sum)
    stdv = Math.sqrt(stds)/ii
    puts 'U0 AVG= ' + format("%3.6f",avgs) + ' stdv = ' + format("%2.4f",stdv*100.0)+ "%"
    ii = uass.size
    avgs = (uass.sum / ii)
    stds = (uass.map{|x| ((x - avgs)/avgs)**2}.sum)
    stdv = Math.sqrt(stds)/ii
    puts 'UA AVG= ' + format("%2.6e",avgs) + ' stdv = ' + format("%2.4f",stdv*100.0)+ "%"
    ii = ubss.size
    avgs = (ubss.sum / ii)
    stds = (ubss.map{|x| ((x - avgs)/avgs)**2}.sum)
    stdv = Math.sqrt(stds)/ii
    puts 'UB AVG= ' + format("%3.6e",avgs) + ' stdv = ' + format("%2.4f",stdv*100.0) + "%"
    
    zz0 = determine_1st vbss,uass 

    ua = zz0[2]
    uc = zz0[1]
    u0 = u0ss[0]
    ub = ubss[0]
    #p [u0,ua,ub,uc]
    bbb = []
    for j in 0..xy.size - 1 do
      bbb <<J_data
      vth = xy[j]["vth"]
      vbs = xy[j]["vbs"]
      bbb[j]["x"] = xy[j]["x"].dup
      bbb[j]["y"] = []  
      for i in 0..xy[j]["x"].size - 1 do
        dx = (xy[j]["x"][i] + vth)/tox
        bbb[j]["y"][i] = (u0/(1 + (ua + uc * vbs) * dx + ub * dx**2)).dup 
      end
    end    

    tag = calc_stdv xy.dup,bbb.dup
    p "total error = #{(tag * 100).round(4)}% @mag = #{(magx - 0.01).round(3)}"

      model.set :U0 => (format("%5.5e",u0)).to_f
      model.set :UA => (format("%5.5e",ua)).to_f
      model.set :UB => (format("%5.5e",ub)).to_f
      model.set :UC => (format("%5.5e",uc)).to_f
      model.save

      u0x = "U0 = " + (model.get :U0).to_s
      uax = "UA = " + (model.get :UA).to_s
      ubx = "UB = " + (model.get :UB).to_s
      ucx = "UC = " + (model.get :UC).to_s
      puts 'Model Parameters SET:'
      puts u0x
      puts uax
      puts ubx
      puts ucx

      zz = []
      @jtable[0]["act"] =" Estimate Ueff "
    
     # data
  end

  ### verification Ueff(Vgs) ###
  def step2_verification_ueff step: 0.2 
    u0  = (@model.get :U0).to_f
    ua  = (@model.get :UA).to_f
    ub  = (@model.get :UB).to_f
    uc  = (@model.get :UC).to_f
    tox = (@model.get :TOX).to_f
    p [u0,ua,ub,uc,tox]
    ueff = change_step(datas: step2_calculate_ueff_vgs_relation(mag: 1.0, vgmf: true),step: step)
    ii   = ueff.size
    for i in 0..ii - 1 do
      ueff[i+ii]      = ueff[i].dup
      ueff[i+ii]["y"] = []
      ueff[i+ii]["z"] = []
      vth             = ueff[i]["vth"].dup
      vbs             = ueff[i]["vbs"].dup
      jj              = ueff[i]["x"].size
      ueff[i]["name"]   = "meas("+ vbs.to_s + ")"
      ueff[i+ii]["name"]= "cal.("+ vbs.to_s + ")"
      ueff[i+ii]["meas"]= false
      ueff[i]["meas"]= true
      for j in 0..jj - 1 do
        dx = (ueff[i+ii]["x"][j] + vth)/tox
        ueff[i+ii]["y"][j] = u0/(1 + (ua + uc * vbs) * dx + ub * dx**2)
      end
    end
    ii = ueff.size / 2
    a = ueff[0..ii - 1 ].dup
    b = ueff[ii..ii * 2 - 1 ].dup
    tmp = calc_stdv a,b
    p tmp
    @jtable[1]["ver_ueff"] = ueff
    list_graph
  end

  ## Calc standard deviation between 2 Curves
  def calc_stdv a,b
      
    f_g = 0.0
    ii  = 0
    
    for i in 0..a.size - 1 do
      ff  = a[i]["y"].dup
      gg  = b[i]["y"].dup
      ii += ff.size
      for j in 0..ff.size - 1 do
        f_g += ((ff[i] - gg[i])/gg[i])**2
      end
    end
    
    stdv = Math.sqrt(f_g)/ii 
    #p format( "stdv = %e",stdv)
    return stdv
  end

  ### -------------------------------------------------

  ###[STEP3] Estimate RDSW & Lint from Vgs-Id(several L)
  #  [STEP3-0] read Id-Vgs-l data            => imitateimitate_measdata
  #  [STEP3-1] Calculate Vth-l               => calculate_vth_l_relation
  #  [STEP3-2] Transform Id-Vgs-L to Rds-L   => transform_id_vgs_to_rd_l
  #  [STEP3-3] Estimate RDSW & LINT
  #  [STEP3-4] Calculation graphs for verification

    
  ###[STEP3-1] Calculate Vth-l::using calculate_vth_vbs_relation

  def calculate_vth_l_relation flg: false, vgs: 0.0,vds: 0.05,vbs: 0.0,lw: [[0.6e-6,4e-6],[0.8e-6,4e-6],[1.0e-6,4e-6],[1.4e-6,4e-6],[2.0e-6,4e-6]] ,mode: "lines",name: ["l=0.6u","l=0.8u","l=1.0u","l=1.4u","l=2.0u"]

    calculate_vth_vbs_relation flg: flg,vgs: vgs,vds: vds,vbs: vbs,lw: lw,mode: mode,name: name
      
    data0 = @jtable[0]
    data0["step"]   = "STEP3"
    data0["act"]    = "STEP3: "
    data0["device"] = ""
    data0["ver"]    = 0.99
      
    write_json @jtable

  end

  #### [STEP3-2] Transform Id-Vgs-L => Rds-L
  def step3_transform_id_vgs_to_rd_l step: 0.5,flg: false ,from: 3.0, to: 5.0
    p [from,to]    
    id   = change_step step: step

    trans         = J_data.dup
    trans["vds"]  = id[0]["vds"]
    trans["vbs"]  = id[0]["vbs"]
    trans["w"]    = id[0]["w"]
    trans["mode"] = id[0]["mode"]
    trans["a"]    = 0.0
    trans["b"]    = 0.0
    trans["meas"] = true
    trans["x"]    = []
    trans["y"]    = []      
    
    vmin          = from
    vmax          = to
    imax          = id[0]["x"].index { |v| v >= vmax }
    imin          = id[0]["x"].index { |v| v >= vmin }
    p [id[0]["x"][imax],imax,id[0]["x"].size - 1]
    zz            = [] 
    z             = trans.dup
    z["x"]        = []
    z["y"]        = []
    z["name"]     = ""

    for i in imin..imax  do #Vgs= 2.0-5.0V(401 points)
      z["name"] = "vgs = #{id[0]["x"][i].round(3)}"
      for j in 0..id.size - 1 do
        ww        = z["w"]*1.0e6
        vds       = z["vds"]
      
        z["vgs"]  = id[j]["x"][i]             ### vgs ###
        z["x"][j] = id[j]["l"].dup                ###  l  ###
        #z["y"][j] = ((id[j]["x"][i] - id[j]["x"][i - 1]) / (id[j]["y"][i] - id[j]["y"][i - 1])/(ww)).round(5).dup  ### rds = 1/Gm ###
        #z["y"][j] = ((id[j]["x"][i]) / (id[j]["y"][i])/(ww)).round(5).dup  ### rds = 1/Gm ###
        z["y"][j]  = vds / (id[j]["y"][i] )*ww  ### rds ###
#        p [vds,ww,vds / (id[j]["y"][i] )*ww, 1/(id[j]["y"][i] ),z["vgs"]]
      end 
      zz[i - imin]      = z.dup
      zz[i - imin]["x"] = z["x"].dup
      zz[i - imin]["y"] = z["y"].dup
      z  = trans.dup
    end

    #calcurate Rds-L curve Rds = a(i)*l + b(i)
    a = []
    b = []
    for i in 0..zz.size - 1 do
      y = determine_1st zz[i]["x"] ,zz[i]["y"]
      a << y[1]
      b << y[2]
      zz[i]["a"] = y[1]
      zz[i]["b"] = y[2]
    end

    rds_l =duplicate_hash(zz)
    for i in 0..rds_l.size - 1 do
      rds_l[i]["y"]    = []
      rds_l[i]["meas"] = false
      #rds_l[i]["x"].insert(0,-rds_l[i]["b"]/rds_l[i]["a"]).dup
      #rds_l[i]["y"].insert(0,0.0).dup
      rds_l[i]["x"].insert(0,-2e-6).dup
      rds_l[i]["y"].insert(0,0.0).dup
      for j in 0..rds_l[i]["x"].size - 1 do
        x = rds_l[i]["x"][j]
        rds_l[i]["y"][j] = rds_l[i]["a"]*x + rds_l[i]["b"]
      end
    end


    # add calculate data(rds_l) to mesure data(zz)
    zz.concat(rds_l)
    ### a,b data set
    zzz ={ "a" => a , "b" => b}
    @jtable[1]["rds_l"] = zz
    @jtable[1]["rds_la"] = zzz


    p  list_graph
    if flg then
      zzz
    else
      true
    end
  end

  ####  [STEP3-3] Estimate RDSW & LINT
  def step3_estimate_lint_rdsw step: 0.5,from:2.0, to: 4.9
    ab = {}
    ab =  step3_transform_id_vgs_to_rd_l flg: true,from: from,to: to,step: step

    a  = ab["a"]
    b  = ab["b"]
      
    rds_l = duplicate_data "rds_l"
  
    zc = {"x"=>[],"y"=>[]}
    absum = 0.0
    abnum = 0
    for i in 0.. a.size - 2 do
      for j in i..a.size - 2 do
        absum += -(b[j+1] -b[j])/(a[j+1]-a[j])
        abnum += 1
      end
    end

    abavg =absum/abnum
    p [absum,abnum,abavg]
      
    a_avg = a.sum.to_f/a.size  
    b_avg = b.sum.to_f/b.size 
    p [a_avg,b_avg,-b_avg/a_avg] 
    x0    = abavg  - 1e-8
    dx    = 1e-9
    stdv0 = 0
    for i in 0..a.size - 1 do
      stdv0 += ((a[i] * x0 +b[i]) - (a_avg * x0 + b_avg))**2/(a_avg * x0 + b_avg).abs 
    end
    stdv0 = Math.sqrt(stdv0)/a.size
    stdv1 = 0
    x1   = (x0 + dx).round(12)
    for i in 0..a.size - 1 do
      stdv1 += ((a[i] * x1 +b[i]) - (a_avg * x1 + b_avg))**2/(a_avg * x1 + b_avg).abs 
    end
    stdv1 = Math.sqrt(stdv1)/a.size
    ii = 0
    while( (stdv1).abs > 0.001 && ii < 1000 && dx.abs > 1e-12) do
      x0    = x1.round(12)
      stdv0 = stdv1
      stdv1 = 0
      x1   = (x0 + dx).round(14)
      for i in 0..a.size - 1 do
        stdv1 += ((a[i] * x1 +b[i]) - (a_avg * x1 + b_avg))**2/(a_avg * x1 + b_avg).abs 
      end
      stdv1 = Math.sqrt(stdv1)/a.size
    #  p [ii,x1,(a_avg * x1 + b_avg),stdv1,stdv0,dx.round(14)]
      if (stdv1 > stdv0) then
        dx = - (dx * 0.5).round(14)
      end
      ii += 1
    end
    p "n = #{ii},LINT =#{(x1/2.0).round(12)},RDSW =#{(a_avg * x1 + b_avg).round(2)},STDV=#{stdv1.round(4)},dx = #{dx.round(16)}"
  end

=begin
  model.set :LINT => format("%5.3e",xmin/2.0)
  model.set :RDSW => format("%5.3e",rr)
  model.save
  puts "Model parameter Set:"
  puts format('[Lint = %5.3e]',xmin/2.0)
  puts format('[Wint = %5.3e]',0.0)
  puts format('[RDSW = %5.3e]',rr)
  
  zzzz =[]
  for i in 0..rds_l.size - 1 do
    #if i == 0 then
    #end
    if (i % 50 ==0) then
      zzzz << rds_l[i]
    end
  end
    
  zz ={"x"=>[],"y"=> [],"meas"=>false}
  zz["x"][0] = 0.0
  zz["y"][0] = rr
  zz["x"][1] = -xmin
  zz["y"][1] = rr
  zz["x"][2] = -xmin
  zz["y"][2] = 0.0

  @jtable[1]["rds_l"] << zz.dup
  list_graph
  true
=end

  ### [STEP6 VTH-L(NLX,DVT0,DVT1,DVT2,ETA0,ETAB)]
  ### [STEP6-1] step6_get_vth_l source: "meas",VTH0: 0.6064,lvth: 30e-6  :: create VTH-L Curve
  ### [STEP6-2] step6_calc_vth leff: 0.6e-6,weff: 4.0e-6,vbs: 0.0,cond: [lt0,xdep0,phi,vbi]
  ### [STEP6-3] step6_estimate_dvt0_dvt1_dvt2_eta0_etab

  ### [STEP3-1] step3_get_vth_l source: "meas",VTH0: 0.6064,lvth: 30e-6  :: create VTH-L Curve
  def step6_get_vth_l source: "measdata",data: [[0.0,30e-6,30e-6,0.6434],[-0.5,30e-6,30e-6,0.8525],[-1.0,30e-6,30e-6,1.0264]]
    meas = @jtable[1]["measdata"].dup
    lint = (@model.get :LINT).to_f
    wint = (@model.get :WINT).to_f

    vth_data = {"leff"=>[],"weff"=>[],"vbs"=>[],"vth"=> []}
    for i in 0..meas.size - 1 do
      vth_data["leff"][i] = meas[i]["l"] - 2 * lint
      vth_data["weff"][i] = meas[i]["w"] + 2 * lint
      vth_data["vbs"][i]  = meas[i]["vbs"]
      vth_data["vth"][i]  = meas[i]["vth"]
    end

    #for i in 0..data.size - 1 do
      vth_data["vbs"]  << 0.0
      vth_data["leff"] << 30e-6 - 2 * lint
      vth_data["weff"] << 30e-6 + 2 * wint
      vth_data["vth"]  << 0.6434    
    #end
    p vth_data
  end
  ###[STEP6] Vth-l
  ###[STEP6](1)determine vth-l
  def step6_determine_vth_l 
    id = step6_get_vth_l source: "measdata",data: [[0.0,30e-6,30e-6,0.6434],[-0.5,30e-6,30e-6,0.8525],[-1.0,30e-6,30e-6,1.0264]]
    lint = (@model.get :LINT).to_f
    wint = (@model.get :WINT).to_f
    rdsw = (@model.get :RDSW).to_f
    tox  = (@model.get :TOX).to_f
    nch  = (@model.get :NCH).to_f
    na   = (@model.get :NSUB).to_f
    xj   = (@model.get :XJ).to_f
    dvt0 = (@model.get :DVT0).to_f
    dvt1 = (@model.get :DVT1).to_f
    nlx  = (@model.get :NLX).to_f
    cox  = Eox*E0/tox
    nds  =  1.0e20
    nsub =  6.0E16
    # parameters
    vbi   = K*T/Q * Math.log(nch * nds/(Ni**2))
    xdep  = Math.sqrt(2.0 * ESi * E0 * (phis - vbs)/(Q * nch))
    xdep0 = Math.sqrt(2.0 * ESi * E0 * phis/(Q * nch))    
    lt    = Math.sqrt(ESi * E0 * xdep/(E0 / tox)) * (1.0 + dvt2 * vbs)
    lt0   = Math.sqrt(ESi * E0 * xdep/(E0 / tox))
    ltw   = Math.sqrt(ESi * E0 * xdep/(E0 / tox)) * (1.0 + dvt2w * vbs)

    phis  = 2.0*Vt*Math.log(na/Ni)
    sphis = Math.sqrt(phis)
  #   vbi   = 1.009
    # This Is for PN Junc Vbi
    # Not for MOS Vbi
    
    vv    = vbi - phis
    lt = Math.sqrt(ESi*E0*xdep/cox)
    p format('Vbi =%f : phs = %f lt = %e',vbi,phis,lt)
    dvt0 = 2.2
    dvt1 = 0.53

    zz = {"x"=>[],"y"=>[],"vth0"=>[],"vv"=>[]}
    zz["vth0"] = 0.6434
    zz["vv"] = vv
    for i in 0..id["leff"].size - 1 do
      
      l =  (id[i]["leff"]) / lt
      vth = id[i]["vth"]
      zz["x"] << l
      zz["y"] << vth.abs
    end  # end of i
    a = calc_vth_l zz,dvt0,dvt1
    if a > 1e-3 then
      d0 =0.01
      d1 =0.01
      for i in 0..10000 do
        a = calc_vth_l zz,dvt0,dvt1
        b = calc_vth_l zz,dvt0+d0,dvt1
        c = calc_vth_l zz,dvt0,dvt1+d1
        if b >= a then
#        p "no dvt0"
          d0 = - d0*0.5
          dvt0 =dvt0 + d0
        else
          dvt0 = dvt0 + d0
        end
        if c >= a then
#p "no dvt1"
          d1 = -d1*0.5
          dvt1 =dvt1 + d1
        else
          dvt1 =dvt1 + d1
        end
#      dvt0 =dvt0 +d0
#      dvt1 =dvt1 +d1
      end
      puts [i,a,dvt0,dvt1]
      model.set :DVT0 => format("%4.3f",dvt0).to_f
      model.set :DVT1 => format("%4.3f",dvt1).to_f
      model.set :VTH0 => vth0
      model.save
      puts format('[VTH0 = %4.3fV]',vth0)
      puts format('[DVT0 = %4.3f]',dvt0)
      puts format('[DVT1 = %4.3f]',dvt1)
    end
    zz={"x"=> [],"y"=>[]}
    for i in 1..100 do
      zz["x"][i-1] = i*1e-6
      x = zz["x"][i-1]
      l =  (x -2.0*lint) / lt
      zz["y"][i-1] = vth0.abs - dvt0*(Math.exp(-dvt1*l/2.0)+2.0*Math.exp(-dvt1*l))*vv
    end
    [zz]
  end
    
  ##[STEP6](2)Vth-l calc
  def calc_vth_l id,dvt0,dvt1

    vth0 = id["vth0"].abs
    vv  = id["vv"]
    y2 = 0
    for i in 0..id["x"].size - 1 do
      x = id["x"][i]
      y0 =id["y"][i].abs
      y =vth0 - dvt0*(Math.exp(-dvt1*x/2.0)+2.0*Math.exp(-dvt1*x))*vv
      y2 += y2 + (y - y0)**2
    #  p [i,x,y,y0,dvt0,dvt1,y2]
    end  # end of i
    y2
  end

  #step6
  def vth_by_l vth
    vthx = []
     for j in 0..vth[0]["x"].size - 1 do
       z = { "x"=>[] , "y"=>[] }
       
     for i in 0..vth.size - 1 do
        z[i]["x"][j] = vth[i]["x"][j]
        z[i]["y"][j] = vth[i]["y"][j]
      end
      vhtx << z.dup
    end
    vthx
  end

  ### [STEP6-2] step6_calc_vth leff: 0.6e-6,weff: 4.0e-6,vbs: 0.0,cond: [lt0,xdep0,phi,vbi]



  ### [STEP6-3] step6_estimate_dvt0_dvt1_dvt2_eta0_etab

  ### Normalize Vds-Id  *****
  def get_normalize_id table0
    table = table0.dup
    meas = table[1]["measdata"]
    for i in 0..meas.size - 1 do
      l = meas[i]["l"]
      w = meas[i]["w"]
      #      p [meas[i]["y"].size,l/w]
      #      ii = meas[i]["y"].size
      for j in 0..meas[i]["y"].size - 1 do
        meas[i]["y"][j] *= l/w
      end
    end
    table[0]["act"] +="Id Normalize"
    table
  end

  ### 2nd-order least squares method y = Ax^2 + Bx + C
  def determine_2nd x  , y

    x11,x12,x13 = 0,0,0
    x21,x22,x23 = 0,0,0
    x31,x32,x33 = 0,0,0
    y1 ,y2 ,y3  = 0,0,0
    f1 ,f2 ,f3  = 0,0,0

    for i in 0..(x.size) - 1 do
      x11 += x[i]**4
      x12 += x[i]**3
      x13 += x[i]**2
      x21  = x12
      x22  = x13
      x23 += x[i]
      x31  = x22
      x32  = x23
      x33 += 1
      y1  += x[i]**2 * y[i]
      y2  += x[i] * y[i]
      y3  += 1.0*y[i]
    end
    a1 = [x11,x12,x13]
    a2 = [x21,x22,x23]
    a3 = [x31,x32,x33]
    yy = [y1,y2,y3]

    f = Matrix.rows([a1,a2,a3], true).inv
    k = Matrix.columns([yy])
    z = f*k

    a = z[0,0]
    b = z[1,0]
    c = z[2,0]

    [a,b,c]
  end

  ### 1st Order least squares method
  ###1st case determin
  def determine_1st x , y
    x11,x12 = 0,0
    x21,x22 = 0,0
    y1 ,y2  = 0,0
    for i in 0..x.size - 1 do
      x11 += x[i]**2
      x12 += x[i]
      x21 = x12
      x22 += 1.0
      y1  += x[i]*y[i]
      y2  += y[i]
    end
    a1 = [x11,x12]
    a2 = [x21,x22]
    yy = [y1,y2]
    
    f = Matrix.rows([a1,a2], true).inv
    k = Matrix.columns([yy])
    
    z = f*k
    
    a = z[0,0]
    b = z[1,0]

    [0 , a , b]
  end
  
end   # end of Bsim3Fit

if $0 == __FILE__
  $:.unshift('.')
  $:.unshift('./ade_express')
  #load 'j_pack.rb'

  Dir.chdir 'C:\Users\swear\Documents\Seafile\My Library\bsim3'
  puts "DIR=#{Dir.pwd}"   
  params = {
    wdir: 'C:\Users\swear\Documents\Seafile\My Library\bsim3',
    model: 'models/test.lib',
    model_org: "models/MinedaPTS06_TT",
    jtable: 'json/test0329.json',
    jtable1: 'json/test0416_1.json'
  }

  mf = Bsim3Fit.new params[:model], params[:model_org]
  ### [STEP0]::Id-Vgs Curve Reads ###
  mf.imitate_measdata File.join(params[:wdir], params[:jtable])
  ### [STEP1]::Estimate VTH[VTH0,K1,K2] ###
  mf.calculate_vth_vbs_relation flg: false, vgs: 0.0, vds: 0.05, vbs: [0.0, -0.5 , -1.0, -1.5,-2.0], lw: [[30e-6,30e-6]], mode: "lines",
                                name: ["vbs=0.0","vbs=-0.5","vbs=-1.0","vbs=-1.5","vbs=-2.0"]
  mf.print_condition
=begin  
  mf.step1_estimate_vth_k1_k2
  mf.step1_calc_vth_vbs
  mf.plot_graph "vthdata"

  ### [STEP2]::Estimate UEFF[U0,UA,UB,UC] ###
  mf.step2_estimation_u0_ua_ub_uc mag: 3.5,err: 1.0e-6 
  p mf.list_graph
  mf.step2_verification_ueff
  mf.plot_graph "ver_ueff"
=end
  ###[STEP3] Estimate RDSW & Lint from Vgs-Id(several L)
  #  [STEP3-0] read Id-Vgs-l data            => imitateimitate_measdata
  #  [STEP3-1] Calculate Vth-l               => calculate_vth_l_relation
  #  [STEP3-2] Transform Id-Vgs-L to Rds-L   => transform_id_vgs_to_rd_l
  #  [STEP3-3] Estimate RDSW & LINT
  #  [STEP3-4] Calculation graphs for verification
  
  mf = Bsim3Fit.new params[:model], params[:model_org]
  #  [STEP3-0] read Id-Vgs-l data            => imitateimitate_measdata
  mf.imitate_measdata File.join(params[:wdir], params[:jtable1])
  #  [STEP3-1] Calculate Vth-l               => calculate_vth_l_relation
  mf.calculate_vth_l_relation flg: false, vgs: 0.0,vds: 0.05,vbs: 0.0,lw: [[0.6e-6,4e-6],[0.8e-6,4e-6],[1.0e-6,4e-6],[1.4e-6,4e-6],[2.0e-6,4e-6]] ,mode: "lines",name: ["l=0.6u","l=0.8u","l=1.0u","l=1.4u","l=2.0u"]
  mf.print_condition
  mf.step6_get_vth_l source: "meas",data:[[0.0,30e-6,30e-6,0.6434],[-0.5,30e-6,30e-6,0.8525],[-1.0,30e-6,30e-6,1.0264]]
  mf.step6_determine_vth_l
  #  [STEP3-2] Transform Id-Vgs-L to Rds-L   => transform_id_vgs_to_rd_l
  #mf.step3_transform_id_vgs_to_rd_l step: 0.5,flg: false,from: 3.5,to: 4.9
  ####  [STEP3-3] Estimate RDSW & LINT
  mf.step3_estimate_lint_rdsw step: 0.1,from:3.5,to: 5.0
  mf.plot_graph "rds_l"
  #p mf.model.get :RDSW
  #p mf.model.get :LINT
end
