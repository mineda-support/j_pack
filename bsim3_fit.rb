['alta2', 'j_pack','j_pack/ade_express'].each{|f| a_path = File.join(ENV['HOMEPATH']||ENV['HOME'], f)
  $:.unshift a_path if File.exist?(a_path) && !$:.include?(a_path)
}
$:.unshift '.' if File.exist?(".") && !$:.include?('.')
#exitload "j_pack.rb"

p "PWD = " + Dir.pwd

require 'csv'
require 'matrix'
require 'json'
require 'compact_model'
require 'roo'
require 'roo-xls'
require 'gnuplot'

Q   = 1.6e-19   unless defined? Q
ESi = 12        unless defined? ESi
Eox = 3.9       unless defined? Eox
E0  = 8.854e-12 unless defined? E0
T   = 300.0     unless defined? T
K   = 1.38e-23  unless defined? K
Ni  = 1.5e+10   unless defined? Ni
Vt  = K*T/Q     unless defined? Vt  
NDS = 1.0e20    unless defined? NDS

J_data  = {"x" => [],"y" => [],"z" => [],"vgs"=> 0.0,"vds"=>0.0,"vbs" =>0.0,"vth" =>0.0,"l"=>0.0,"w"=>0.0,"gmax"=>[],"name" =>"","mode" =>"lines","meas"=>true,"type" =>:body} unless defined? J_data
#J_table = [{"plot_number"=>0,"title"=>[],"title_x"=>[],"title_y"=>[],"xaxis_is_log"=> [],"yaxis_is_log"=> [],"day"=> "","basename"=> "","filename" => "","ver"=>0.99,"act"=> " ","device"=> "","dir"=>"json/","ext"=> "json","step"=> ""},{},{}] unless defined? J_table
J_table = [{"plot_number"=>0,"title"=>[],"title_x"=>[],"title_y"=>[],"xaxis_is_log"=> [],"yaxis_is_log"=> [],"day"=> "","basename"=> "","filename" => "","ver"=>0.99,"act"=> " ","device"=> "","dir"=>"json/","ext"=> "json","step"=> ""},{"plotdata"=> [],"measdata"=> []}] unless defined? J_table
### xls file read point ###
M_IdVgs = [{ "vgs"=> 'H' ,"ids"=>'A',"vds"=>'B'},
       { "vgs"=> 'S' ,"ids"=>'L',"vds"=>'M'},
       { "vgs"=> 'AD',"ids"=>'W',"vds"=>'X' } ]         

class ModelFit
  attr_accessor :model, :model_org, :jtable, :phis
  def initialize model="models/test.lib", model_org="models/MinedaPTS06_TT"
    @model     = CompactModel::new model
    @model_org = CompactModel::new model_org
    @jtable    = duplication_j_table 
    nsub = (@model.get :NSUB).to_f
    @phis = 2.0*Vt*Math.log(nsub/Ni)
  end

  # read csv file to table(like json type)
  def read_csv csv_file = './csv/test1.csv'
    table = CSV.table(csv_file).by_col!
  end
  #private :read_csv

  def read_measdata ctable, basename='json/vgid'
    meas = []
    for j in 0..ctable.headers.size - 2 do 
      meas[j] = duplicate_j_data
      meas[j]["name"] =ctable.headers[j+1]
      meas[j]["x"]= [].dup
      meas[j]["y"]= [].dup

      for i in 0..ctable.size - 1 do
        meas[j]["x"][i] = ctable[0][i].round(5).dup
        meas[j]["y"][i] = ctable[j+1][i].dup
      end
    end

    @jtable[1]["measdata"] = meas.dup
    @jtable[0]["basename"]= basename.dup
    @jtable[0]["act"] = "csv to json,"

    return true
  end

  # read json file to table
  def read_json json_file
    if !(FileTest.exist?(json_file)) then
      p json_file + " does not exist!!"
      return
    end
    File.open(json_file,mode = "r") do |f|
      table = JSON.load(f)
    end
  end

  private :read_json

  
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
    p "ver =#{data["ver"]}"
    data["ver"] = ver
    if data["device"].empty? then
      device = ""
    else
      device = "_" + data["device"]
    end

    new_file = dir + name + "_" + step + device + ".ver" + ver.to_s + "." + ext
    data["filename"]=new_file
    data["day"] = Time.now.to_s
    data["ver"] = ver
    p "write_json file =" + new_file

    File.open(new_file, 'w') do |file|
      JSON.dump(table, file)
    end
  end

  ### save table to json_file
  def save_json table=@jtable
    data = table[0]
    dir  = data["dir"]
    name = data["basename"]
    ext  = data["ext"]

    new_file = dir + name + "." + ext
    data["filename"]=new_file
    data["day"] = Time.now.to_s
    data["ver"] = 1.0
    p "save_json file =" + new_file

    File.open(new_file, 'w') do |file|
      JSON.dump(table, file)
    end
  end

  def read_idvgs_xls dir: "IdVgs", files:{},graph:["Vds0_05","Vds_1"],is_lw: false,l:10e-6,w:60e-6,vbs:0
    files.each{|v| # indidual xls-files read and act
      if is_lw then
        array = v.split( /(\w+)L([0-9]+).*W([0-9]+)/)
        dname = array[1]+ "_NL#{array[2]}W#{array[3]}"
        dl    = array[2].to_f * 1e-6 
        dw    = array[3].to_f * 1e-6 
      else
        dname = v.split(".xls")
        dl    = l
        dw    = w
      end

      # read xls file

      s = Roo::Excel.new([dir , v].join("/"))
      sheet = s.sheet(0)

      for i in 0..graph.size - 1 do
        tmp = duplicate_j_data
        tmp["name"] = dname
        tmp["l"] = dl
        tmp["w"] = dw
        tmp["vbs"] = 0
        tmp["x"] = sheet.column(M_IdVgs[i]["vgs"]).dup        #copy vgs
        tmp["x"].shift()
        for j in 0..tmp["x"].size - 1 do
          tmp["x"][j] = tmp["x"][j].round(4)        #rounding off at 1e-4
        end
        tmp["y"]   = sheet.column(M_IdVgs[i]["ids"])          #copy ids
        tmp["y"].shift()
        tmp["vds"] = sheet.cell(M_IdVgs[i]["vds"],2).round(3) #rounding off at 1e-3
        @jtable[1][graph[i]] << tmp.dup
      end
    }
  end

end #end ModelFit

class Bsim3Fit < ModelFit

  ### [STEP00]  Delta-Vth Calculation ###
  def step0_calculate_vth_l model=@model,files,vbs: 0.0,vds: 0.05,l: 100e-6,w:100e-6
    #model parameters
    m_name = files["process"]
    m_model = files["model"]
    m_size = files["size"]

    model.load m_model

    lint   =  (model.get:LINT).to_f 
    wint   =  (model.get:WINT).to_f 
    leff   =  l - 2.0 * lint
    weff   =  w + 2.0 * wint

    tox    =  (model.get:TOX).to_f 
    nch    =  (model.get:NCH).to_f
    if (model.get:NSUB).nil? then
      nsub   =  6.0E16
    else
      nsub   =  (model.get:NSUB).to_f
    end
    vth0   =  (model.get:VTH0).to_f
    k1     =  (model.get:K1).to_f
    k2     =  (model.get:K2).to_f
    k3     =  (model.get:K3).to_f
    k3b    =  (model.get:K3B).to_f
    nlx    =  (model.get:NLX).to_f
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
   
    p " process,tox,nch,nsub, nlx,  k1, k2, k3,  k3b,  w0, dvt0,  dvt1,  dvt2,  dsub,  eta0,  etab,  dvt0w,  dvt1w,  dvt2w" 
    p "#{m_name},#{tox},#{nch},#{nsub}, #{nlx}, #{k1}, #{k2}, #{k3}, #{k3b}, #{w0}, #{dvt0}, #{dvt1}, #{dvt2}, #{dsub}, #{eta0}, #{etab}, #{dvt0w}, #{dvt1w}, #{dvt2w}"
 
    # parameters
    phis  = 2.0*Vt*Math.log(nsub/Ni)
    phiss = Math.sqrt(phis)
    vbi   = Vt * Math.log(nch  * NDS / (Ni**2))
    vbi2  = Vt * Math.log(nsub * NDS / (Ni**2))

    xdep  = Math.sqrt(2.0 * ESi * E0 * (phis - vbs)/(Q * nch))
    xdep0 = Math.sqrt(2.0 * ESi * E0 * phis/(Q * nch))    
    lt    = Math.sqrt(ESi * E0 * xdep/(E0 / tox)) * (1.0 + dvt2 * vbs)
    lt0   = Math.sqrt(ESi * E0 * xdep/(E0 / tox))
    ltw   = Math.sqrt(ESi * E0 * xdep/(E0 / tox)) * (1.0 + dvt2w * vbs)

    p "phis,vbi,vbi2,xdep,xdep0,lt,lt0,ltw"
    p "#{phis},#{vbi},#{vbi2},#{xdep},#{xdep0},#{lt},#{lt0},#{ltw}"
    p " phis = #{phis.to_s}  Vbi = #{vbi.to_s} Vbi2 = #{vbi2.to_s}   Vbi - phis = #{(vbi - phis).to_s}  Vbi2 - phis = #{(vbi2 - phis).to_s}"
    out = duplication_j_table
  
    out[1]["plotdata"]=[]
    out[1]["plotdata"][0] = duplicate_j_data
    out[1]["plotdata"][0]["meas"] = false
    out[1]["plotdata"][0]["w"]    = w
    out[1]["plotdata"][0]["vds"]  = 0.05
    out[1]["plotdata"][0]["vbs"]  = 0.0
    out[1]["plotdata"][0]["meas"] = false

    out[1]["measdata"]=[]
    for i in 0..4 do
      out[1]["measdata"][i] = duplicate_j_data
      out[1]["measdata"][i]["meas"] = true
      out[1]["measdata"][0]["w"]    = w
      out[1]["measdata"][0]["vds"]  = 0.05
      out[1]["measdata"][0]["vbs"]  = 0.0
    end

    for i in 0..60 do # 0.1u~100u
      lr = (10 ** (i*0.05))*1e-7
      leff = lr - 2 * lint
      if leff >= m_size then
        delta10  = k1 * Math.sqrt(1.0 + nlx/leff - 1.0)
        delta11  =( k3 + k3b * vbs) * tox/(weff + w0) * phis
        delta20  = - dvt0 * (Math.exp(-dvt1 * leff / (2.0 * lt )) + 2.0 * Math.exp(- dvt1 * leff / lt ))* (vbi2 - phis)
        delta30  = -        (Math.exp(-dsub * leff / (2.0 * lt0)) + 2.0 * Math.exp(- dsub * leff / lt0))* (eta0 + etab * vbs)
        delta40  = dvt0w * (Math.exp(-dvt1w * (weff * leff)  / (2.0 * ltw)) + 2.0 * Math.exp(- dvt1w * (weff * leff) / ltw))*(vbi - phis)
      
        out[1]["measdata"][0]["x"] << leff
        out[1]["measdata"][0]["y"] << delta10
        out[1]["measdata"][1]["x"] << leff
        out[1]["measdata"][1]["y"] << delta20
        out[1]["measdata"][2]["x"] << leff
        out[1]["measdata"][2]["y"] << delta30
        out[1]["measdata"][3]["x"] << leff
        out[1]["measdata"][3]["y"] << delta40
        out[1]["measdata"][4]["x"] << leff
        out[1]["measdata"][4]["y"] << delta11
        out[1]["plotdata"][0]["x"] << leff
        out[1]["plotdata"][0]["y"] << delta10 + delta20 + delta30 + delta40 + delta11
      end
    end
    out[1]["plotdata"][0]["name"] = m_name
    out[1]["measdata"][0]["name"] = m_name + "(NLX)"
    out[1]["measdata"][1]["name"] = m_name + "(D1)"
    out[1]["measdata"][2]["name"] = m_name + "(D2)"
    out[1]["measdata"][3]["name"] = m_name + "(L&W)"
    out[1]["measdata"][4]["name"] = m_name + "(W)"

    return out

  end

  ### [STEP0]  Get Spice parameters for Vth
  def step0_get_vth_param model=@model,files,vbs:0.0

    #model parameters
    m_name = files["process"]
    m_model = files["model"]
    m_size = files["size"]

    model.load m_model

    lint   =  (model.get:LINT).to_f 
    wint   =  (model.get:WINT).to_f 
    #leff   =  l - 2.0 * lint
    #weff   =  w + 2.0 * wint

    tox    =  (model.get:TOX).to_f 
    if (model.get:NSUB).nil? then
      nch = 1.7E+017
    else
      nch    =  (model.get:NCH).to_f
    end
    if (model.get:NSUB).nil? then
      nsub   =  6.0E16
    else
      nsub   =  (model.get:NSUB).to_f
    end
    vth0   =  (model.get:VTH0).to_f
    k1     =  (model.get:K1).to_f
    k2     =  (model.get:K2).to_f
    k3     =  (model.get:K3).to_f
    k3b    =  (model.get:K3B).to_f
    nlx    =  (model.get:NLX).to_f
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
    vbi   = Vt * Math.log(nch  * NDS / (Ni**2))
    vbi2  = Vt * Math.log(nsub * NDS / (Ni**2))
    xdep  = Math.sqrt(2.0 * ESi * E0 * (phis - vbs)/(Q * nch))
    xdep0 = Math.sqrt(2.0 * ESi * E0 * phis/(Q * nch))    
    lt    = Math.sqrt(ESi * E0 * xdep/(E0 / tox)) * (1.0 + dvt2 * vbs)
    lt0   = Math.sqrt(ESi * E0 * xdep/(E0 / tox))
    ltw   = Math.sqrt(ESi * E0 * xdep/(E0 / tox)) * (1.0 + dvt2w * vbs)

    out = "#{m_name},#{tox},#{nch},#{nsub},#{lint},#{wint}, #{vth0},#{nlx}, #{k1}, #{k2}, #{k3}, #{k3b}, #{w0}, #{dvt0}, #{dvt1}, #{dvt2}, #{dsub}, #{eta0}, #{etab}, #{dvt0w}, #{dvt1w}, #{dvt2w}, #{phis},#{vbi},#{vbi2},#{xdep},#{xdep0},#{lt},#{lt0},#{ltw}"
    return out
  end

  ### table data check
  def data_check
    data=@jtable[1]
    if data["plotdata"].size > 0 then
      plot =data["plotdata"]
      for i in 0..plot.size - 1 do
        puts " [plotdata][#{i}] size = #{plot[i]["y"].size} null = #{plot[i]["y"].index(nil)}"
      end
    end
    if data["measdata"].size > 0 then
      meas =data["measdata"]
      for i in 0..meas.size - 1 do
        puts " [measdata][#{i}] size = #{meas[i]["y"].size} null = #{meas[i]["y"].index(nil)}"
      end
    end
  end

  ### table data cut to N
  def data_cut num:501
    data = @jtable[1]
    if data["plotdata"].instance_of?(Array) then
      plot =data["plotdata"]
      for i in 0..plot.size - 1 do
        plot[i]["x"].slice!(num,plot[i]["x"].size - 1)
        plot[i]["y"].slice!(num,plot[i]["y"].size - 1)
      end
    end
    if data["measdata"].instance_of?(Array) then
      meas =data["measdata"]
      for i in 0..meas.size - 1 do
        meas[i]["x"].slice!(num,meas[i]["x"].size - 1)
        meas[i]["y"].slice!(num,meas[i]["y"].size - 1)
      end
    end
  end

  # Caliculate AVG and STDV
  def calc_avg_stdv data=[1,2,3,4,5] , x:0
    stddata      = {"x"=>0,"y"=>[],"avg"=> 0,"stdv"=>0}
    stddata["y"] = data

    mean =  stddata["y"].sum/stddata["y"].size
    stds =  stddata["y"].map{|x| ((x - mean)**2)}.sum
    stdv =  Math.sqrt(stds/stddata["y"].size)
    stddata["avg"] = mean.round(4)
    stddata["stdv"] = stdv.round(4)
    return stddata
  end

  ###[STEP1]Define Vth Parameter (VTH0,K1,K2) Sub ###
  def convert_vth_lwvdvb param: "l",process: "PTS06"
    meas = duplicate_j_data
    for i in 0..@jtable[1]["measdata"].size - 1 do
      if param == 'i' then
        meas["x"][i] = i
      else
        meas["x"][i] = @jtable[1]["measdata"][i][param]
      end
      meas["y"][i] = @jtable[1]["measdata"][i]["vth"].round(5)
    end
    meas["l"]     = @jtable[1]["measdata"][0]["l"]
    meas["w"]     = @jtable[1]["measdata"][0]["w"]
    meas["vbs"]   = @jtable[1]["measdata"][0]["vbs"]
    meas["vds"]   = @jtable[1]["measdata"][0]["vds"]
    meas["name"]  = process
    meas["sweep"] = "#{param} sweep"
    meas["meas"]  = true
  
    return meas
  end


  def print_condition
    #p "filename =  " + @jtable[0]["dir"] + @jtable[0]["basename"] + @jtable[0]["ext"]
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
  #### (-1) J_table Duplication
  def duplication_j_table
    ddata = [{},{}]
    ddata[0] = J_table[0].dup
    ddata[1]["plotdata"] = []
    ddata[1]["measdata"] = []
    return ddata
  end

  #### (0) J_data Duplication ####
  def duplicate_j_data 
    data = J_data.dup
    data["x"] = []
    data["y"] = []
    data["z"] = []
    return data
  end

  #### (1) "measdata" duplication #####
  def duplicate_data from = "measdata"
    if from.instance_of?(Array) then
      data = from.dup
      #p "from = Array, size =#{data.size}"
    else
      data  = @jtable[1][from].dup
      p "from = #{from}, size =#{data.size}"
    end

    ddata =[]
    for i in 0..data.size - 1 do
      ddata[i] = duplicate_j_data
      ddata[i] = duplicate_hash data[i]
    end
    return ddata
  end

  #### (1.5) Hash duplication #####
  def duplicate_hash from 
    data  = from.dup
    # p data.size
    if data.instance_of?(Array) then
      ddata = []
      if data == ddata then
        return ddata
      end
      
      for j in 0..data.size - 1 do
        d_list = data[j].keys
        d_list.each {|x|
        
          if data[j][x].instance_of?(Array) then
            ddata[j][x] = []
            for i in 0..data[i][x].size - 1 do
              ddata[j][x][i] =data[j][x][i].dup
            end
          else
            ddata[x] = data[x].dup
          end
        }
        end
    elsif data.instance_of?(Hash) then
      ddata = duplicate_j_data
      if data == ddata then
        return ddata
      end
      d_list = data.keys
      d_list.each {|x|
        if data[x].instance_of?(Array) then
          ddata[x] = []
          for i in 0..data[x].size - 1 do
            ddata[x][i] =data[x][i].dup
          end
        else
          ddata[x] = data[x].dup
        end
      }
    else
      p "#{from} is not Array nor Hash"
      return data
    end 
    return ddata
  end

  ### (2) duplicate @jtable[0]  ###
  def duplicate_head
    head = @jtable[0].dup

    dhead = J_table[0].dup
    dhead["day"]       = head["day"].dup 
    dhead["basename"]  = head["basename"].dup 
    dhead["filename"]  = head["filename"].dup 
    dhead["ver"]       = head["ver"].dup 
    dhead["act"]       = head["act"].dup 
    dhead["device"]    = head["device"].dup 
    dhead["dir"]       = head["dir"].dup 
    dhead["ext"]       = head["ext"].dup 
    dhead["step"]      = head["step"].dup
    return dhead
  end

  ### (3) duplicate jtable ####
  def duplicate_jtable data: "measdata"
    qtable = duplication_j_table
    qtable[0] = duplicate_head
    qtable[1]["measdata"] = duplicate_data(data)
    return qtable
  end

  ### (4) duplicate whole table ####
  def duplicate_whole_table
    qtable = duplication_j_table
    qtable[0] = duplicate_head
    dlist = list_graph
    dlist.each{|v|
      qtable[1][v] = duplicate_data(v)
  }
  #  qtable[1]["measdata"] = duplicate_data(data)
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
    #p "head = #{head} "
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
    
    [head["dir"]].each { |dir|
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

    @jtable[1][dist] = duplicate_data  source     #@jtable[1][source]
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
        p "graph['measdata'] do not delelete"
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
  def add_graph source: "measdata",target: "plotdata"
    ss = duplicate_data(source)
    i_ss = ss.size
    for i in 0..i_ss -1
      @jtable[1][target] << ss[i]
    end
  end
    
  ### Storage calc data ("gmdata","simpledata","vthdata#)
  def plot_graph gname = "measdata"
    target = list_graph
    if @jtable[1].key?(gname) != true  then
      p gname +" is not exist " + target.to_s
      return false
    end
    ptable = duplicate_whole_table
    #ptable[0]             = duplicate_head
    ptable[1]["measdata"] = [].dup
    ptable[1]["plotdata"] = [].dup
    #pdata                 = duplicate_data(gname)
    pdata                 = ptable[1][gname]
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
  

  # [STEP-1] Read json_file to @jtable
  def read_table json_file
    if !File.exist?(json_file) then
      p "File::#{json_file} is not exist!!"
      return
    end
    p "json_file =#{json_file} " #, @jtanle[0] = #{@jtable[0]}"
    tmp = (read_json json_file).dup
    @jtable[1]["plotdata"] = duplicate_data tmp[1]["plotdata"]
    if tmp[1]["measdata"] != nil then
      @jtable[1]["measdata"] = duplicate_data tmp[1]["measdata"]
    else
      @jtable[1]["measdata"] = []
    end
    @jtable[0] = duplicate_head
    @jtable[0]["basename"] = File.basename(json_file,".json")
    @jtable[0]["ver"] = 0.99
    write_json @jtable
  end

  # [STEP0] Read amd Convert data from "plotdata" to "measdata" and save file.converted.json
  def imitate_measdata json_file
    dtable    = (read_json json_file).dup
    p "json_file =#{json_file} " #, @jtanle[0] = #{@jtable[0]}"
    @jtable[0] = J_table[0].dup
    @jtable[1]["measdata"] = dtable[1]["measdata"].dup
    @jtable[1]["plotdata"] = dtable[1]["plotdata"].dup
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
      #p "lw    lw.size = #{lw.size}  lw[#{i}]= #{lw[i]}"
      if lw.size == 1 then
        meas[i]["l"] =lw[0][0]
        meas[i]["w"] =lw[0][1]
      elsif lw.size == 2 && lw[0].is_a?(Numeric) && lw[1].is_a?(Numeric) then
        meas[i]["l"] =lw[0]
        meas[i]["w"] =lw[1]
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
      meas[i]["vth"] = ((gmm * vgm - idm)/gmm - meas[i]["vds"]/2.0).round(5)
      #meas[i]["name"] = "vbs= " + meas[i]["vbs"].to_s
    end

    @jtable[0]["act"] += "cal [vth,gm],"
    @jtable[0]["step"] = "STEP1"
    
    #@jtable[0]["device"] = ""
    #write_json @jtable
  end

  ###[STEP1-0] ###
  def step1_calc_vth_from_data target: "measdata",vds: 0.05,vbs: 0.0,lw: [10e-6,60e-6]
    ## calculate VTH0 
    @jtable[1]["measdata"] = duplicate_data target
    calculate_vth_vbs_relation flg: false, vgs: 0.0, vbs: vbs ,vds: vds, mode: "lines" , lw: [l,w] , name: "Vds= #{vds.to_s}"
    @jtable[1][target] = duplicate_data "measdata"
  end




  ###[STEP1]Define Vth Parameter (VTH0,K1,K2) Sub ###
  def convert_vth na: 6e+16

    na =(@odel.get :NSUB).to_f

    phis = @phis
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
    if (model.get:NSUB).nil? then
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
    #nds    =  1.0e20

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
    vbi   = K*T/Q * Math.log(nch * NDS/(Ni**2))
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
      gm << duplicate_j_data
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
        gmdata[jj+i] = duplicate_j_data
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
      meas1[i] = duplicate_j_data
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
  def step2_calculate_ueff_vgs_relation mag: 1.0, vgmf: true
    
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
  def step2_estimation_u0_ua_ub_uc err: 1e-5,mag: 1.5 ,isvbs: false

    tox  =(model.get :TOX).to_f
  
    @jtable[0]["step"] = "STEP2" 
    tag = 1.0
    magx = 1.0
    while(tag >= err && magx <= mag)  do 
      xy = (step2_calculate_ueff_vgs_relation mag: magx,vgmf: false).dup
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
    if isvbs==false then
      uc = 0.0
      model.set :U0 => (format("%5.5e",u0)).to_f
      model.set :UA => (format("%5.5e",ua)).to_f
      model.set :UB => (format("%5.5e",ub)).to_f
      model.set :UC => (format("%5.5e",uc)).to_f
      model.save
      return
    end

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
      bbb << duplicate_j_data
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

    trans         = duplicate_j_data
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
    rds_l = []
    for i in 0..zz.size - 1 do
      rfs_l[i] = duplicate_hash(zz[i])
    end
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
    @jtable[1]["Rds_L"] = zz
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
      
    rds_l = duplicate_data "Rds_L"
  
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

    @model.set :LINT => (x1/2.0).round(9)
    @model.set :RDSW => (a_avg * x1 + b_avg).round(2)
    @model.save

  end

  ### [step3-3-2] LINT & RDSW estimate Id-Vgs directly
  def step3_estimate_lint_rdsw2 step: 0.1,from:2.0, to: 5.0
    ddata = duplicate_data "measdata"
    u0  =  (@model.get :U0).to_f
    ua  =  (@model.get :UA).to_f
    ub  =  (@model.get :UB).to_f
    uc  =  (@model.get :UC).to_f
    tox =  (@model.get :TOX).to_f
    lint = (@model.get :LINT).to_f.round(8)
    #lint = 0.01e-6
    rdsw = (@model.get :RDSW).to_f.round(0)
    rdsw = 200
    vsat = (@model.get :VSAT).to_f
    wint = (@model.get :WINT).to_f
    cox = Eox * E0 / tox
    data = []
    for i in 0..ddata.size - 1 do
      jmax          = ddata[0]["x"].index { |v| v >= to }
      jmin          = ddata[0]["x"].index { |v| v >= from }
      data[i] = duplicate_hash ddata[i]
      data[i]["x"] = []
      data[i]["y"] = []
      data[i]["z"] = []
      for j in jmin..jmax do
        data[i]["x"] << ddata[i]["x"][j]
        data[i]["y"] << ddata[i]["y"][j]
      end
    end
    abulk = 1.0
    @jtable[1]["test"] = [] 
    calc = step3_calc_id_vds data: data, lint: lint,rdsw: rdsw,wint: wint,u0: u0, ua: ua,ub: ub,uc: uc,cox: cox,vsat: vsat,tox: tox,abulk: abulk
    stdv0 = step3_calc_stdv ori: data,calc: calc
    p "Initial LINT = #{lint.round(9)}  RDSW = #{rdsw} :: STDV = #{stdv0}"
    
    ### stdv  > 1e-6 loop
    dlint = 1e-7
    drdsw = 100   
    calc_lp = step3_calc_id_vds data: data, lint: lint+dlint,rdsw: rdsw,wint: wint,u0: u0, ua: ua,ub: ub,uc: uc,cox: cox,vsat: vsat,tox: tox,abulk: abulk
    stdv_lp = step3_calc_stdv ori: data,calc: calc_lp
    calc_lm = step3_calc_id_vds data: data, lint: lint-dlint,rdsw: rdsw,wint: wint,u0: u0, ua: ua,ub: ub,uc: uc,cox: cox,vsat: vsat,tox: tox,abulk: abulk
    stdv_lm = step3_calc_stdv ori: data,calc: calc_lm
    if stdv_lp > stdv_lm then
      dlint = - dlint
    end
    calc_rp = step3_calc_id_vds data: data, lint: lint,rdsw: rdsw+drdsw,wint: wint,u0: u0, ua: ua,ub: ub,uc: uc,cox: cox,vsat: vsat,tox: tox,abulk: abulk
    stdv_rp = step3_calc_stdv ori: data,calc: calc_rp
    calc_rm = step3_calc_id_vds data: data, lint: lint,rdsw: rdsw-drdsw,wint: wint,u0: u0, ua: ua,ub: ub,uc: uc,cox: cox,vsat: vsat,tox: tox,abulk: abulk
    stdv_rm = step3_calc_stdv ori: data,calc: calc_rm
    if stdv_rp > stdv_rm then
      drdsw =  -drdsw
    end

    i = 0
    while(stdv0 >1.0e-4 && dlint.abs >= 1e-10 )  do
      calc = step3_calc_id_vds data: data, lint: lint+dlint,rdsw: rdsw,wint: wint,u0: u0, ua: ua,ub: ub,uc: uc,cox: cox,vsat: vsat,tox: tox,abulk: abulk
      stdv = step3_calc_stdv ori: data,calc: calc
  
      p "N= #{i} LINT = #{(lint+dlint).round(9)}  RDSW = #{rdsw} STDV = #{stdv.round(12)} DLINT = #{dlint.round(9)} "

      if (stdv < stdv0) then 
        stdv0 =stdv
        lint += dlint
      else
      #  stdv0 =stdv
        dlint = -dlint/10
      end
      i += 1
    end

    i = 0
    while(stdv0 >1.0e-4 && drdsw.abs >=0.01)  do
      calc = step3_calc_id_vds data: data, lint: lint+dlint,rdsw: rdsw,wint: wint,u0: u0, ua: ua,ub: ub,uc: uc,cox: cox,vsat: vsat,tox: tox,abulk: abulk
      stdv = step3_calc_stdv ori: data,calc: calc
  
      p "N= #{i} LINT = #{(lint).round(9)}  RDSW = #{rdsw+drdsw} STDV = #{stdv.round(12)} DRDSW = #{drdsw.round(0)} "

      if (stdv < stdv0) then 
        stdv0 =stdv
        rdsw += drdsw
      else
        drdsw = -drdsw/10
      end
      i += 1
    end
  
    du0 = 0.001
    i = 0
    while(stdv0 >1.0e-4 && du0.abs >=1e-7)  do
      calc = step3_calc_id_vds data: data, lint: lint+dlint,rdsw: rdsw,wint: wint,u0: u0+du0, ua: ua,ub: ub,uc: uc,cox: cox,vsat: vsat,tox: tox,abulk: abulk
      stdv = step3_calc_stdv ori: data,calc: calc
  
      p "N= #{i} LINT = #{(lint).round(9)}  RDSW = #{rdsw} STDV = #{stdv.round(12)} U0 = #{(u0 +du0).round(10)} "

      if (stdv < stdv0) then 
        stdv0 =stdv
        u0 += du0
      else
        du0 = -du0/10
      end
      i += 1
    end

    @jtable[1]["test"] = []
    for i in 0..calc.size - 1 do  
      @jtable[1]["test"] << data[i].dup
      @jtable[1]["test"] << calc[i].dup
    end
    @model.set :LINT => lint.round(10)
    @model.set :RDSW => rdsw.round(3)
    @model.set :U0   => u0.round(10)
    @model.save
    p "Final LINT = #{lint.round(10)}, RDSW = #{rdsw.round(3)}, U0 = #{u0.round(10)}"
  end

  ### Calculate stdv between meas & calc  ###
  def step3_calc_stdv ori: [],calc: []
    tmp = 0
    num = 0
    for i in 0..ori.size - 1 do
      num += ori[i]["x"].size
      for j in 0..ori[i]["x"].size - 1 do
        tmp += ((calc[i]["y"][j] - ori[i]["y"][j])/ori[i]["y"][j])**2
      end
    end
    result = Math.sqrt(tmp)/num
    return result
  end

  ### Calculate Id-Vgs(withRDSW) ####
  def step3_calc_id_vds data: @jtable[1]["Vds0_05"], lint: 0,rdsw: 0,wint: 0,u0: 0, ua: 0,ub: 0,uc: 0,cox: 0,vsat: 0,tox: 0,abulk: 1
    
    ddata = []
    for i in 0..data.size - 1 do
      leff = data[i]["l"] - 2 * lint
      weff = data[i]["w"] + 2 * wint
      rds  = rdsw /(weff * 1.0e6)
      vds  = data[i]["vds"]

      vbs  = data[i]["vbs"]
      vth  = data[i]["vth"]
      ddum = duplicate_hash data[i]
      ddum["meas"] =false
      ddum["x"] = []
      ddum["y"] = []
      ddum["z"] = []
      for j in 0..data[i]["x"].size - 1 do
        vgs  = data[i]["x"][j]
        ueff = u0/(1 + (ua + uc * vbs)*((vgs + 2.0 * vth)/tox) + ub * ((vgs + 2.0 * vth)/tox)**2)
        esat = 2.0 * vsat / ueff
        id0  = ueff * cox * weff/leff *(1/(1 + vds/(esat * leff)))*(vgs - vth - (abulk * vds) /2)*vds
        ids  = id0/(1.0 + (rds * id0/vds))
        ddum["x"][j] = vgs
        ddum["y"][j] = ids
        ddum["z"][j] = id0
      end
      ddata << ddum
    end
    return ddata
  end

  ### [STEP6-0] get delta vth ####
  def step6_get_delta_vth vth_l = @jtable[1]["VTH_L"]
    data = duplicate_data vth_l
    data[2] = duplicate_hash data[1]

    vth0 = (@model.get :VTH0).to_f
    
    for j in 0..data[0]["x"].size - 1 do
      data[2]["y"][j] -= data[0]["y"][j]
      data[2]["name"] = "VTH@Vds=#{data[2]["vds"]} - VTH@Vds=#{data[0]["vds"]}"
      for i in 0..data.size - 2 do
        data[i]["y"][j] -= vth0
        data[i]["name"] = "VTH@Vds=#{data[i]["vds"]} - (#{vth0})"
      end
    end
    out = step6_calculate_vth_l vbs: 0.0,vds: 0.05,l: 10e-6,w:60e-6
    for i in 0..out.size - 2 do
    #  data << out[i].dup
    end
    imax = out.size - 1
    for i in 0..out[0]["x"].size - 1 do
      out[imax]["y"][i] -= vth0
    end
    out[imax]["name"] = "Vds= #{out[imax]["vds"]}"
    data << out[imax].dup
    out1 = step6_calculate_vth_l vbs: 0.0,vds: 0.95,l: 10e-6,w:60e-6
    data << out1[2].dup
    out2 = step6_calculate_vth_l vbs: 0.0,vds: 1.0,l: 10e-6,w:60e-6
    for i in 0..out2[0]["x"].size - 1 do
      out2[imax]["y"][i] -= vth0
    end
    out2[imax]["name"] = "Vds= #{out2[imax]["vds"]}"
    data << out2[imax].dup

    return data
  end
 
  ### [STEP6-1]  Calculate VTH-L Curves ###
  def step6_calculate_vth_l vbs: 0.0,vds: 0.05,l: 100e-6,w:100e-6
  
    lint   =  (model.get:LINT).to_f 
    wint   =  (model.get:WINT).to_f 
    tox    =  (model.get:TOX).to_f 
    nch    =  (model.get:NCH).to_f
    if (model.get:NSUB).nil? then
      nsub   =  6.0E16
    else
      nsub   =  (model.get:NSUB).to_f
    end
    vth0   =  (model.get:VTH0).to_f
    k1     =  (model.get:K1).to_f
    k2     =  (model.get:K2).to_f
    k3     =  (model.get:K3).to_f
    k3b    =  (model.get:K3B).to_f
    nlx    =  (model.get:NLX).to_f
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
 
    leff   =  l - 2.0 * lint
    weff   =  w + 2.0 * wint
    # parameters
    phis  = @phis
    phiss = Math.sqrt(phis)
    vbi   = Vt * Math.log(nch  * NDS / (Ni**2))
    xdep  = Math.sqrt(2.0 * ESi * E0 * (phis - vbs)/(Q * nch))
    xdep0 = Math.sqrt(2.0 * ESi * E0 * phis/(Q * nch))    
    lt    = Math.sqrt(ESi * xdep * tox / Eox) * (1.0 + dvt2 * vbs)
    lt0   = Math.sqrt(ESi * xdep0 * tox / Eox)
    ltw   = Math.sqrt(ESi * xdep * tox / Eox) * (1.0 + dvt2w * vbs)
    xdep  = Math.sqrt(2.0 * ESi * E0 * (phis - vbs)/(Q * nch))
    xdep0 = Math.sqrt(2.0 * ESi * E0 * phis/(Q * nch))    
    lt    = Math.sqrt(ESi * xdep * tox / Eox) * (1.0 + dvt2 * vbs)
    lt0   = Math.sqrt(ESi * xdep0 * tox / Eox)

    p "dvt0=#{dvt0} dvt1=#{dvt1} dsub=#{dsub} eta0=#{eta0}"
    out = []

    for i in 0..5 do
      out[i] = duplicate_j_data
      out[i]["meas"] = false
      out[i]["w"]    = w
      out[i]["l"]    = l
      out[i]["vds"]  = vds
      out[i]["vbs"]  = vbs
    end

    for i in 0..20 do # 1u~10u
      lr = (10 ** (i*0.05))*1e-6
      leff = lr - 2 * lint
      if leff > 0 then
        
        delta10  = k1 * (Math.sqrt(1.0 + nlx/leff) - 1.0)
        delta11  =( k3 + k3b * vbs) * tox/(weff + w0) * phis
        delta20  = - dvt0 * (Math.exp(-dvt1 * leff / (2.0 * lt )) + 2.0 * Math.exp(- dvt1 * leff / lt ))* (vbi - phis)
        delta30  = -        (Math.exp(-dsub * leff / (2.0 * lt0)) + 2.0 * Math.exp(- dsub * leff / lt0))* (eta0 + etab * vbs) * vds
        delta40  = dvt0w * (Math.exp(-dvt1w * (weff * leff)  / (2.0 * ltw)) + 2.0 * Math.exp(- dvt1w * (weff * leff) / ltw))*(vbi - phis)
      
        out[0]["x"] << lr
        out[0]["y"] << delta10
        out[1]["x"] << lr
        out[1]["y"] << delta20
        out[2]["x"] << lr
        out[2]["y"] << delta30
        out[3]["x"] << lr
        out[3]["y"] << delta40
        out[4]["x"] << lr
        out[4]["y"] << delta11
        out[5]["x"] << lr
        out[5]["y"] << vth0 + delta10 + delta20 + delta30 + delta40 + delta11
      end
    end
    out[0]["name"] =  "[2](NLX)"
    out[1]["name"] =  "[4](D1)"
    out[2]["name"] =  "[5](D2)"
    out[3]["name"] =  "[6](L&W)"
    out[4]["name"] =  "[3](W)"
    out[5]["name"] =  "VTH(L)"

    return out
  end

  ### [STEP6-3] extract Dsub,Eta0
  def step6_calculate_dsub_eta0 ddata: [],vds: 0.95,vbs: 0,dsub: 0.56,eta0: 0.0,etab: 0.0,w: 60e-6
  data =[]  
  data = duplicate_data ddata
    
    lint   =  (model.get:LINT).to_f 
    wint   =  (model.get:WINT).to_f 
    tox    =  (model.get:TOX).to_f 
    nch    =  (model.get:NCH).to_f
    if (model.get:NSUB).nil? then
      nsub   =  6.0E16
    else
      nsub   =  (model.get:NSUB).to_f
    end
    vth0   =  (model.get:VTH0).to_f
    k1     =  (model.get:K1).to_f
    k2     =  (model.get:K2).to_f
    k3     =  (model.get:K3).to_f
    k3b    =  (model.get:K3B).to_f
    nlx    =  (model.get:NLX).to_f
    w0     =  (model.get:W0).to_f
    dvt0   =  (model.get:DVT0).to_f
    dvt1   =  (model.get:DVT1).to_f
    dvt2   =  (model.get:DVT2).to_f
    #dsub   =  (model.get:DSUB).to_f
    #eta0   =  (model.get:ETA0).to_f
    etab   =  (model.get:ETAB).to_f
    dvt0w  =  (model.get:DVT0W).to_f
    dvt1w  =  (model.get:DVT1W).to_f
    dvt2w  =  (model.get:DVT2W).to_f
   
  #  leff   =  l - 2.0 * lint
    weff   =  w + 2.0 * wint
    # parameters
    phis  = @phis
    phiss = Math.sqrt(phis)
    vbi   = Vt * Math.log(nch  * NDS / (Ni**2))

    xdep  = Math.sqrt(2.0 * ESi * E0 * (phis - vbs)/(Q * nch))
    xdep0 = Math.sqrt(2.0 * ESi * E0 * phis/(Q * nch))    
    lt    = Math.sqrt(ESi * xdep * tox / Eox) * (1.0 + dvt2 * vbs)
    lt0   = Math.sqrt(ESi * xdep0 * tox / Eox)
    ltw   = Math.sqrt(ESi * xdep * tox / Eox) * (1.0 + dvt2w * vbs)

    #p "phis=#{phis.round(6)},vbi=#{vbi.round(6)},xdep=#{xdep.round(6)},xdep0=#{xdep0.round(6)},lt=#{lt.round(6)},lt0=#{lt0.round(6)},ltw=#{ltw.round(6)}"
    out = []

    for i in 0..0 do
      out[i] = duplicate_j_data
      out[i]["meas"] = false
      out[i]["w"]    = w
      out[i]["l"]    = 0
      out[i]["vds"]  = vds
      out[i]["vbs"]  = vbs
      out[i]["name"] = "VTH(D2)"
    end
    for i in 0..data[0]["x"].size - 1 do
        leff = data[0]["x"][i] - 2 * lint
        #delta20  = - dvt0 * (Math.exp(-dvt1 * leff / (2.0 * lt )) + 2.0 * Math.exp(- dvt1 * leff / lt ))* (vbi - phis)
        #p "dleat20 =#{delta20.round(5)} DVT0=#{dvt0.round(5)} DVT1=#{dvt1.round(5)} (vbi - phis)=#{(vbi - phis).round(5)} AA = #{(Math.exp(-dvt1 * leff / (2.0 * lt )) + 2.0 * Math.exp(- dvt1 * leff / lt )).round(5)}"

        #delta10  = k1 * (Math.sqrt(1.0 + nlx/leff) - 1.0)
        #delta11  =( k3 + k3b * vbs) * tox/(weff + w0) * phis
        #delta20  = - dvt0 * (Math.exp(-dvt1 * leff / (2.0 * lt )) + 2.0 * Math.exp(- dvt1 * leff / lt ))* (vbi - phis)
        delta30  = -        (Math.exp(-dsub * leff / (2.0 * lt0)) + 2.0 * Math.exp(- dsub * leff / lt0))* (eta0 + etab * vbs) * vds
        #delta40  = dvt0w * (Math.exp(-dvt1w * (weff * leff)  / (2.0 * ltw)) + 2.0 * Math.exp(- dvt1w * (weff * leff) / ltw))*(vbi - phis)
      
        out[0]["x"] << data[0]["x"][i]
        out[0]["y"] << delta30
    end

    return out
  end

  def initialize_params_vth_l
    params = {
      "TOX"  => (@model.get :TOX).to_f,
      "NCH"  => (@model.get :NCH).to_f,
      "VTH0" => (@model.get :VTH0).to_f ,
      "K1"   => (@model.get :K1).to_f ,
      "K2"   => (@model.get :K2).to_f,
      "PHI"  => @phis ,

      "DVT0" => (@model.get :DVT0).to_f,
      "DVT1" => (@model.get :DVT1).to_f,
      "DVT2" => (@model.get :DVT2).to_f,
      "LINT" => (@model.get :LINT).to_f,
      "WINT" => (@model.get :WINT).to_f,
      "DSUB" => (@model.get :DSUB).to_f,
      "ETA0" => (@model.get :ETA0).to_f,
      "LT0" =>  1e-7,
      "ETAB" => (@model.get :ETAB).to_f,
      "NFACTOR" => (@model.get :NFACTOR).to_f
    }

    xdep0 = Math.sqrt(2.0 * ESi * E0 * @phis/(Q * params["NCH"]))    
    params["LT0"]   = Math.sqrt(ESi * xdep0 * params["TOX"] / Eox)
    p params
    p "Xdep0 = #{xdep0}"    
    return params
  end

  def calc_xdep0(params)
    esi  = ESi    ##params["ESI"]   # シリコン誘電率
    e0   = E0     ##params["E0"]    # 真空誘電率
    phi  = @phis  ##params["PHI"]   # 表面ポテンシャル
    nch  = params["NCH"]   # チャネルドーピング
    q    = Q      ##params["Q"]     # 電荷量

    xdep0 = Math.sqrt(2.0 * esi * e0 * phi / (q * nch))
    return xdep0
  end  

  def calc_lt0(params)
    esi   = ESi  ##params["ESI"]
    eox   = Eox  ##params["EOX"]
    tox   = params["TOX"]
    xdep0 = calc_xdep0(params)

    lt0 = Math.sqrt(esi * xdep0 * tox / eox)
    return lt0
  end
 


  def vth_long(params, vbs)
    vth0 = params["VTH0"]
    k1   = params["K1"]
    k2   = params["K2"]
    phi  = params["PHI"]

    sqrt_term = Math.sqrt(phi - vbs) - Math.sqrt(phi)

    vth = vth0 + k1 * sqrt_term - k2 * vbs
    return vth
  end

  def vth_sce(params, l, vbs)
    dvt0 = params["DVT0"]
    dvt1 = params["DVT1"]
    dvt2 = params["DVT2"]
    phi  = params["PHI"]
    lint = params["LINT"]

    leff = l - 2.0 * lint

    theta = dvt0 * Math.exp(-dvt1 * leff / (2.0 * Math.sqrt(phi - vbs)))
    delta = theta * (phi - vbs) + dvt2 * vbs

    return delta
  end

  def dvth_dibl(params, l, vds, vbs)
    dsub = params["DSUB"]
    eta0 = params["ETA0"]
    etab = params["ETAB"]
    lt0  = params["LT0"]
    lint = params["LINT"]

    leff = l - 2.0 * lint

    dibl_coeff =
      dsub * Math.exp(-leff / lt0) +
      eta0 +
      etab * vbs

    dvth = - dibl_coeff * vds
    return dvth
  end


  def dvth_dibl(params, l, vds, vbs)
    dsub = params["DSUB"]
    eta0 = params["ETA0"]
    etab = params["ETAB"]
    lint = params["LINT"]

    lt0  = calc_lt0(params)
    leff = l - 2.0 * lint

    dibl_coeff =
      dsub * Math.exp(-leff / lt0) +
      eta0 +
      etab * vbs

    return -dibl_coeff * vds
  end


  def bsim_vth(params, vds, vbs, l)
    # 1. 長チャネルしきい値
    vth = vth_long(params, vbs)

    # 2. 短チャネル効果（SCE）
    vth -= vth_sce(params, l, vbs)

    # 3. DIBL（物理モデル）
    vth += dvth_dibl(params, l, vds, vbs)

    return vth
  end

  def step6_estimate_dsub_eta0 ori: []
    data = duplicate_data ori # measured data
    tox  = (@model.get :TOX ).to_f.round(12)
    nch  = (model.get:NCH).to_f
    lint = (@model.get :LINT).to_f.round(9)
    dsub = (@model.get :DSUB).to_f.round(8)
    eta0 = (@model.get :ETA0).to_f.round(8)
    etab = (@model.get :ETAB).to_f.round(8)

    # parameters
    #cox = Eox * E0 / tox
    phis  = @phis
    #xdep  = Math.sqrt(2.0 * ESi * E0 * (phis - vbs)/(Q * nch))
    xdep0 = Math.sqrt(2.0 * ESi * E0 * phis/(Q * nch))    
    #lt    = Math.sqrt(ESi * xdep * tox / Eox) * (1.0 + dvt2 * vbs)
    lt0   = Math.sqrt(ESi * xdep0 * tox / Eox)
    p "Initial DSUB = #{dsub}  ETA0 = #{eta0} ETAB = #{etab}"

    cal = duplicate_j_data # {"x" => [],"y" => [],"z" => [],"vgs"=> 0.0,"vds"=>0.0,"vbs" =>0.0,"vth" =>0.0,"l"=>0.0,"w"=>0.0,"gmax"=>[],"name" =>"","mode" =>"lines","meas"=>true}
    out = duplicate_j_data # {"x" => [],"y" => [],"z" => [],"vgs"=> 0.0,"vds"=>0.0,"vbs" =>0.0,"vth" =>0.0,"l"=>0.0,"w"=>0.0,"gmax"=>[],"name" =>"","mode" =>"lines","meas"=>true}
    ### estimate routine
    for i in 0.data[0]["x"].size - 1 do
      cal["x"][i] = data[0]["x"][i] ### L ###
      cal["y"][i] = data[1]["y"][i] - data[0]["y"][i]
      out["x"][i] = data[0]["x"][i] ### L ###
    end
    cal["vds"] = data[1]["vds"] - data[0]["vds"] ###deltaVds( 1 - 0.05)
    out["vds"] = cal["vds"] 
    for i in 0..out["x"].size - 1 do
      out["y"] = dvth_dibl l:l ,vds:out["vds"] ,vbs: 0.0,dsub: dsub,eta0: eta0,etab: etab,lt0: lt0, lint: lint 
    end


    ### end estimate
  
   
    @model.set :DSUB => dsub.round(4)
    @model.set :ETA0 => eta0.round(4)
    @model.save

    p "final DSUB = #{dsub.round(2)}, ETA0 = #{eta0.round(2)}, STDV =#{stdv0.round(6)}"
  end

  ### [STEP6-5] Caliculate VTH[4] ###
  def step6_calculate_dvt0_dvt1 ddata: [] ,vds: 0.05,vbs: 0,dvt0: 2.2,dvt1: 0.53,dvt2: -0.032,w: 60e-6
    data =[]  
    data = duplicate_data ddata
    
    lint   =  (model.get:LINT).to_f 
    wint   =  (model.get:WINT).to_f 
    tox    =  (model.get:TOX).to_f 
    nch    =  (model.get:NCH).to_f
    if (model.get:NSUB).nil? then
      nsub   =  6.0E16
    else
      nsub   =  (model.get:NSUB).to_f
    end
    vth0   =  (model.get:VTH0).to_f
    #k1     =  (model.get:K1).to_f
    #k2     =  (model.get:K2).to_f
    #k3     =  (model.get:K3).to_f
    #k3b    =  (model.get:K3B).to_f
    #nlx    =  (model.get:NLX).to_f
    #w0     =  (model.get:W0).to_f
    #dvt1   =  (model.get:DVT1).to_f
    #dvt2   =  (model.get:DVT2).to_f
    dsub   =  (model.get:DSUB).to_f
    eta0   =  (model.get:ETA0).to_f
    #etab   =  (model.get:ETAB).to_f
    #dvt0w  =  (model.get:DVT0W).to_f
    #dvt1w  =  (model.get:DVT1W).to_f
    #dvt2w  =  (model.get:DVT2W).to_f
   
    weff   =  w + 2.0 * wint
    # parameters
    phis  = @phis
    phiss = Math.sqrt(phis)
    vbi   = Vt * Math.log(nch  * NDS / (Ni**2))

    xdep  = Math.sqrt(2.0 * ESi * E0 * (phis - vbs)/(Q * nch))
    xdep0 = Math.sqrt(2.0 * ESi * E0 * phis/(Q * nch))    
    lt    = Math.sqrt(ESi * xdep * tox / Eox) * (1.0 + dvt2 * vbs)
    lt0   = Math.sqrt(ESi * xdep0 * tox / Eox)
    #ltw   = Math.sqrt(ESi * xdep * tox / Eox) * (1.0 + dvt2w * vbs)

    #p "phis=#{phis.round(6)},vbi=#{vbi.round(6)},xdep=#{xdep.round(6)},xdep0=#{xdep0.round(6)},lt=#{lt.round(6)},lt0=#{lt0.round(6)},ltw=#{ltw.round(6)}"
    out = []

    for i in 0..0 do
      out[i] = duplicate_j_data
      out[i]["meas"] = false
      out[i]["w"]    = w
      out[i]["l"]    = 0
      out[i]["vds"]  = vds
      out[i]["vbs"]  = vbs
      out[i]["name"] = "VTH(D4)"
    end
    for i in 0..data[0]["x"].size - 1 do
        leff = data[0]["x"][i] - 2 * lint
        #delta20  = - dvt0 * (Math.exp(-dvt1 * leff / (2.0 * lt )) + 2.0 * Math.exp(- dvt1 * leff / lt ))* (vbi - phis)
        #p "dleat20 =#{delta20.round(5)} DVT0=#{dvt0.round(5)} DVT1=#{dvt1.round(5)} (vbi - phis)=#{(vbi - phis).round(5)} AA = #{(Math.exp(-dvt1 * leff / (2.0 * lt )) + 2.0 * Math.exp(- dvt1 * leff / lt )).round(5)}"

        #delta10  = k1 * (Math.sqrt(1.0 + nlx/leff) - 1.0)
        #delta11  =( k3 + k3b * vbs) * tox/(weff + w0) * phis
        delta20  = - dvt0 * (Math.exp(-dvt1 * leff / (2.0 * lt )) + 2.0 * Math.exp(- dvt1 * leff / lt ))* (vbi - phis)
        #delta30  = -        (Math.exp(-dsub * leff / (2.0 * lt0)) + 2.0 * Math.exp(- dsub * leff / lt0))* (eta0 + etab * vbs) * vds
        #delta40  = dvt0w * (Math.exp(-dvt1w * (weff * leff)  / (2.0 * ltw)) + 2.0 * Math.exp(- dvt1w * (weff * leff) / ltw))*(vbi - phis)
      
        out[0]["x"] << data[0]["x"][i]
        out[0]["y"] << delta20
    end
  p "dvt0=#{dvt0} dvt1=#{dvt1} dsub=#{dsub} eta0=#{eta0}"
    return out
  end
  
  ### [STEP6-6] Estimate Dvt0 , Dvt1 ###
  
  def step6_estimate_dvt0_dvt1 ori: []
    data = duplicate_data ori
    tox  = (@model.get :TOX ).to_f.round(12)
    lint = (@model.get :LINT).to_f.round(9)
    wint = (@model.get :WINT).to_f.round(9)
    dvt0 = (@model_org.get :DVT0).to_f.round(8)
    dvt1 = (@model_org.get :DVT1).to_f.round(8)
    dvt2 = (@model.get :DVT2).to_f.round(8)
    cox = Eox * E0 / tox
    @jtable[1]["test"] = [] 
    dvt1 = 1.0
    vds = 0.05
    calc  = step6_calculate_dvt0_dvt1 ddata: data ,vds: vds,vbs: 0,dvt0: dvt0,dvt1: dvt1,dvt2: dvt2,w: 60e-6
    stdv0 = step6_calc_stdv ori: data,calc: calc
    p "Initial DVT0 = #{dvt0}  DVT1 = #{dvt1} DVT2 = #{dvt2}:: STDV = #{stdv0}"
    
    ddvt0 = 0.1

    ddvt1 = 0.01

    calc_dp = step6_calculate_dvt0_dvt1 ddata: data ,vds: vds,vbs: 0,dvt0: (dvt0 + ddvt0),dvt1: dvt1,dvt2: dvt2,w: 60e-6
    stdv_dp = step6_calc_stdv ori: data,calc: calc_dp
    calc_dm = step6_calculate_dvt0_dvt1 ddata: data ,vds: vds,vbs: 0,dvt0: (dvt0 - ddvt0),dvt1: dvt1,dvt2: dvt2,w: 60e-6
    stdv_dm = step6_calc_stdv ori: data,calc: calc_dm
    if stdv_dp > stdv_dm then
      ddvt0 = - ddvt0
    end

    calc_ep = step6_calculate_dvt0_dvt1 ddata: data ,vds: vds,vbs: 0,dvt0: dvt0,dvt1: (dvt1 + ddvt1),dvt2: dvt2,w: 60e-6
    stdv_ep = step6_calc_stdv ori: data,calc: calc_ep
    calc_em = step6_calculate_dvt0_dvt1 ddata: data ,vds: vds,vbs: 0,dvt0: dvt0,dvt1: (dvt1 - ddvt1),dvt2: dvt2,w: 60e-6
    stdv_em = step6_calc_stdv ori: data,calc: calc_em
    if stdv_ep > stdv_em then
      ddvt1 = - ddvt1
    end
 
  ### stdv  > 1e-6 loop
    i = 0
    isdvt0 = true

    while(i < 20 && stdv0 >1.0e-4 && ddvt0.abs >= 1e-4 && ddvt1.abs >= 1e-4 )  do
      calc_d = step6_calculate_dvt0_dvt1 ddata: data ,vds: vds,vbs: 0,dvt0: (dvt0 + ddvt0),dvt1: dvt1,dvt2: dvt2,w: 60e-6
      stdv_d = step6_calc_stdv ori: data,calc: calc_d
      calc_e = step6_calculate_dvt0_dvt1 ddata: data ,vds: vds,vbs: 0,dvt0: dvt0,dvt1: (dvt1 + ddvt1),dvt2: dvt2,w: 60e-6
      stdv_e = step6_calc_stdv ori: data,calc: calc_e

      if (stdv_d < stdv_e) then 
        p "N= #{i} DVT0 = #{(dvt0+ddvt0).round(6)}  DVT1 = #{dvt1.round(6)} STDV = #{stdv_d.round(12)} DDVT0 = #{ddvt0.round(6)} "
        if (stdv_d < stdv0) then
          stdv0 =stdv_d
          dvt0 += ddvt0
          isdvt0 =true
        else
          #stdv0 =stdv_d
          dddvt0 = -ddvt0/2
          dvt0 += ddvt0
          isdvt0 = true
        end
      else
        p "N= #{i} DVT0 = #{(dvt0).round(6)}  DVT1 = #{(dvt1 + ddvt1).round(6)} STDV = #{stdv_e.round(12)} DDVT1 = #{ddvt1.round(6)} "
        if (stdv_e < stdv0) then
          stdv0  = stdv_e
          dvt1  += ddvt1
          isdvt0 = false
        else
          #stdv0 =stdv_d
          dvt1 = -ddvt1/10
          dvt1 += ddvt1
          isdvt0 =false
        end
      end
  
      i += 1
    end

    @jtable[1]["DVT0_DVT1"] = []
    for i in 0..calc.size - 1 do  
      @jtable[1]["DVT0_DVT1"] << data[i].dup
      if isdvt0 then
        @jtable[1]["DVT0_DVT1"] << calc_d[i].dup
      else
        @jtable[1]["DVT0_DVT1"] << calc_e[i].dup
      end
    end

    @model.set :DVT0 => dvt0.round(4)
    @model.set :DVT1 => dvt1.round(4)
    @model.save

    p "final DVT0 = #{dvt0.round(2)}, DVT1 = #{dvt1.round(2)}, STDV =#{stdv0.round(6)}"
  end

  ### [STEP6-7] Calculate stdv between meas & calc  ###
  def step6_calc_stdv ori: [],calc: []
    tmp = 0
    num = 0
    for i in 0..ori.size - 1 do
      num += ori[i]["x"].size
      imax = ori[i]["x"].size - 1
      origin = ori[i]["y"][imax]
      for j in 0..ori[i]["x"].size - 2 do
        tmp += ((calc[i]["y"][j]  - ori[i]["y"][j])/ori[i]["y"][j])**2
      end
        tmp += ((calc[i]["y"][imax] - ori[i]["y"][imax]))**2*1e3
        num += 1
    end
    result = Math.sqrt(tmp)/num
    return result
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
  
end   # end of Bsim3Fit < ModelFit

if $0 == __FILE__
  $:.unshift('.')
  $:.unshift('./ade_express')
  #load 'j_pack.rb'

  Dir.chdir     'C:\Users\swear\Documents\Seafile\My Library\bsim3'
  puts          "DIR=#{Dir.pwd}"   
  
  # model lists & datas
  params = {
    wdir:       'kitayama/nmos/',
    model:       'models/test.lib',
    model_org:   "models/test_org.lib",
  
    jtable_l:   "meas_l.json",
    jtable_w:   "meas_w.json",
    ll:           [[3e-6,60e-6],[4e-6,60e-6],[5e-6,60e-6],[6e-6,60e-6],[10e-6,60e-6]],
    lname:        ["l=3u","l=4u","l=5u","l=6u","l=10u"],
    ww:           [[10e-6,60e-6],[10e-6,36e-6],[10e-6,12e-6]],
    wname:        ["w=60u","w=36u","w=12u"]
          } 
  ###  mos parameter calc ###
  #### Simulation process data ###
=begin
  files = [{"process"=>"DEFAULT",  "model"=> params[:model] ,  "jtable"=>params[:jtable_l], "size"=> 1.0e-6,"num"=> 501,
              "lw"=>[[1e-6,100e-6],[2e-6,100e-6],[4e-6,100e-6],[10e-6,100e-6],[20e-6,100e-6],[40e-6,100e-6],[100e-6,100e-6]],"name"=> ["l=1u","l=2u","l=4u","l=10u","l=20u","l=40u","l=100u"]},
           {"process"=>"PTS06",   "model"=> params[:model_pts] ,  "jtable"=>params[:jtable_pts], "size"=> 0.6e-6,"num"=> 501,
             "lw"=>[[0.6e-6,100e-6],[1e-6,100e-6],[2e-6,100e-6],[4e-6,100e-6],[10e-6,100e-6],[20e-6,100e-6],[40e-6,100e-6],[100e-6,100e-6]],"name"=> ["l=0.6u","l=1u","l=2u","l=4u","l=10u","l=20u","l=40u","l=100u"]},
           {"process"=>"ICPS",    "model"=> params[:model_icps] , "jtable"=>params[:jtable_icps], "size"=> 1.0e-6,"num"=> 501,
             "lw"=>[[4e-6,100e-6],[6e-6,100e-6],[10e-6,100e-6],[20e-6,100e-6],[40e-6,100e-6],[100e-6,100e-6]],"name"=> ["l=4u","l=6u","l=10u","l=20u","l=40u","l=100u"]},
           {"process"=>"Citizn",  "model"=> params[:model_ctzn] , "jtable"=>params[:jtable_ctzn], "size"=> 0.35e-6,"num"=> 501,
             "lw"=>[[0.35e-6,100e-6],[0.6e-6,100e-6],[1e-6,100e-6],[2e-6,100e-6],[4e-6,100e-6],[10e-6,100e-6],[20e-6,100e-6],[40e-6,100e-6],[100e-6,100e-6]],"name"=>["l=0.35u","l=0.6u","l=1u","l=2u","l=4u","l=10u","l=20u","l=40u","l=100u"]},
             {"process"=>"tias130", "model"=> params[:model_tias] , "jtable"=>params[:jtable_tias],  "size"=> 0.13e-6,"num"=> 301,
             "lw"=>[[0.13e-6,100e-6],[0.6e-6,100e-6],[1e-6,100e-6],[2e-6,100e-6],[4e-6,100e-6],[10e-6,100e-6],[20e-6,100e-6],[40e-6,100e-6],[100e-6,100e-6]],"name"=>["l=0.13u","l=0.6u","l=1u","l=2u","l=4u","l=10u","l=20u","l=40u","l=100u"]}]
=end

  ### [STEP1] #### Estimate VTH0
  ### [STEP2] Estimate U0,UA,UB,UC
  #=begin
  ### Bsim3Fit Class Create
  mf = Bsim3Fit.new params[:model], params[:model_org]
  mf.jtable[1]["Vds0_05"]     = []
  mf.jtable[1]["Vds_1"]       = []
  mf.jtable[1]["vth_vds"]     = []
  
  ### Read data.xls files and display Vgs-Id & VTH
=begin
  #files =["25R2JUN2_A1_NL6W12.xls",  "25R2JUN2_C1_NL6W12.xls",  "25R2JUN2_E1_NL6W12.xls",
  #        "25R2JUN2_A3_NL6W12.xls",  "25R2JUN2_C3_NL6W12.xls",  "25R2JUN2_E3_NL6W12.xls",
  #        "25R2JUN2_A5_NL6W12.xls",  "25R2JUN2_C5_NL6W12.xls",  "25R2JUN2_E5_NL6W12.xls"]
=end

  files =["25R2JUN2_C3_NL10W60.xls"]
  dir = [params[:wdir],"IdVgs"].join("/")
  l   = 10e-6
  w   = 60e-6
  vbs = 0.0
  vths = []

  mf.read_idvgs_xls dir: dir, files:files,graph:["Vds0_05","Vds_1"],is_lw: true,l:l,w:w,vbs: vbs
  ## calculate VTH0 for 0.05
  target = "Vds0_05"
  vds = 0.05
  mf.jtable[1]["measdata"] = mf.duplicate_data target
  mf.calculate_vth_vbs_relation flg: false, vgs: 0.0, vbs: vbs ,vds: vds, mode: "lines" , lw: [l,w] , name: "Vds= #{vds.to_s}"
  mf.jtable[1][target] = mf.duplicate_data "measdata"

  ## calculate VTH0 for 1.0
  target = "Vds_1"
  mf.jtable[1]["measdata"] = mf.duplicate_data target
  mf.calculate_vth_vbs_relation flg: false, vgs: 0.0, vbs: vbs ,vds: vds, mode: "lines" , lw: [l,w] , name:  "Vds= #{vds.to_s}"
  mf.jtable[1][target] = mf.duplicate_data "measdata"

  ### get vth-vgs curve
  mf.jtable[1]["measdata"] = mf.duplicate_data "Vds0_05"
  mf.add_graph source: "Vds_1",target: "measdata" 
  vths = mf.convert_vth_lwvdvb param: 'vds',process: 'sweep Vds'
  mf.jtable[1]["vth_vds"] << vths
  
  mf.step1_calc_simplemodel
  mf.step1_calc_gmdata
  p mf.list_graph

  #table title access & save
  mf.jtable[0]["basename"] = "nmos_id_vgs_L#{(l*1e6).to_s}W#{(w*1e6).to_s}"
  mf.jtable[0]["dir"]  = [params[:wdir],"json/"].join("/")
  mf.jtable[0]["step"] =>"STEP1"
  mf.write_json

  #plot Vds=0.05 & Vds=1.0 save
  mf.plot_graph "Vds0_05"
  mf.plot_graph "Vds_1"
  mf.plot_graph "vth_vds"
  mf.plot_graph "gmdata"
  #mf.plot_graph ""
  params = mf.initialize_params_vth_l
  #p " NCH =#{params["NCH"]}"
  #p " Xdep0 = #{mf.calc_xdep0(params)} Lt0 = #{mf.calc_lt0(params)}"

  ### [STEP2] Estimate U0,UA,UB,UC err: 1e-5,mag: 3.0 ,isvbs: false
  mf.copy_graph "Vds0_05","measdata",true
  mf.step2_estimation_u0_ua_ub_uc mag: 1.2,err: 1.0e-6,isvbs: false 
  p mf.list_graph
  mf.step2_verification_ueff
  mf.plot_graph "ver_ueff"


  ### [STEP3][STEP5][STEP6][STEP6.5]
=begin

  ### Bsim3Fit Class Create
  mf = Bsim3Fit.new params[:model], params[:model_org]
  mf.jtable[0]["step"] = "STEP3"
  mf.jtable[1]["Vds0_05"]     = []
  mf.jtable[1]["Vds_1"]       = []
  mf.jtable[1]["VTH_L"]       = []
  mf.jtable[1]["Rds_L"]       = []
  mf.jtable[1]["test"]       = []
  
  ### Read data.xls files and display Vgs-Id & VTH
  
  files =["25R2JUN2_C3_NL2W60.xls","25R2JUN2_C3_NL3W60.xls","25R2JUN2_C3_NL4W60.xls",
          "25R2JUN2_C3_NL5W60.xls","25R2JUN2_C3_NL6W60.xls","25R2JUN2_C3_NL10W60.xls"
        ]
  files =["25R2JUN2_C3_NL3W60.xls","25R2JUN2_C3_NL4W60.xls",
          "25R2JUN2_C3_NL5W60.xls","25R2JUN2_C3_NL6W60.xls","25R2JUN2_C3_NL10W60.xls"
        ]

  ### indidual xls-files read and act
  files.each{|v| 
    array = v.split( /(\w+)L([0-9]+).*W([0-9]+)/)

    dname = array[1] + "_NL#{array[2]}W#{array[3]}"
    dl    = array[2].to_f * 1e-6 
    dw    = array[3].to_f * 1e-6 

    # read xls file

    s = Roo::Excel.new( params[:wdir] + 'IdVgs/' + v )
    sheet = s.sheet(0)

    ### for Vds = 0.05V
    Vds0_05 = mf.duplicate_j_data
    Vds0_05["name"] = dname
    Vds0_05["l"] = dl
    Vds0_05["w"] = dw
    Vds0_05["vbs"] =0
    Vds0_05["x"] = sheet.column(m_s["vgs1"]).dup        #copy vgs
    Vds0_05["x"].shift()
    for i in 0..Vds0_05["x"].size - 1 do
      Vds0_05["x"][i] = Vds0_05["x"][i].round(4)        #rounding off at 1e-4
    end
    Vds0_05["y"]   = sheet.column(m_s["ids1"])          #copy ids
    Vds0_05["y"].shift()
    Vds0_05["vds"] = sheet.cell(m_s["vds1"],2).round(3) #rounding off at 1e-3
    #mf.jtable[1]["Vds0_05"] << Vds0_05.dup
    mf.jtable[1]["measdata"] << Vds0_05.dup
  }

  #table title access & save
  ## calculate VTH0
  mf.calculate_vth_l_relation flg: false, vgs: 0.0, vbs: 0 ,vds: 0.05, mode: "lines" , lw: params[:ll] , name: params[:lname]
  mf.print_condition
  ### get vth-vgs curve
  vths = mf.convert_vth_lwvdvb param: 'l',process: 'Vds=50mV'
  vths["meas"] = true
  mf.jtable[1]["VTH_L"] << vths
  mf.copy_graph "measdata" ,"Vds0_05"
  mf.jtable[1]["measdata"] =[]
  
  # indidual xls-files read and act @Vds=1V
  files.each{|v|
    array = v.split( /(\w+)L([0-9]+).*W([0-9]+)/)

    dname = array[1]+ "_NL#{array[2]}W#{array[3]}"
    dl    = array[2].to_f * 1e-6 
    dw    = array[3].to_f * 1e-6 
 
    # read xls file

    s = Roo::Excel.new("kitayama/nmos/IdVgs/" + v)
    sheet = s.sheet(0)

    ### for Vds = 1V
    Vds_1         = mf.duplicate_j_data
    Vds_1["name"] = dname
    Vds_1["l"]    = dl
    Vds_1["w"]    = dw
    Vds_1["vbs"]  = 0
    Vds_1["x"]    = sheet.column(m_s["vgs2"]).dup     #copy vgs2
    Vds_1["x"].shift()
    for i in 0..Vds_1["x"].size - 1 do
      Vds_1["x"][i] = Vds_1["x"][i].round(4)          #rounding off at 1e-4
    end
    Vds_1["y"]   = sheet.column(m_s["ids2"])          #copy ids2
    Vds_1["y"].shift()
    Vds_1["vds"] = sheet.cell(m_s["vds2"],2).round(3) #rounding off at 1e-3
    #mf.jtable[1]["Vds_1"] << Vds_1.dup
    mf.jtable[1]["measdata"] << Vds_1.dup
    mf.jtable[0]["basename"] = "nmos_id_vgs_L#{array[2]}W#{array[3]}"
  } #end of each

  mf.calculate_vth_vbs_relation flg: false, vgs: 0.0, vbs: 0 ,vds: 1.0, mode: "lines" , lw: params[:ll] , name: params[:lname]
  mf.print_condition
  ### get vth-vgs curve
  vths = mf.convert_vth_lwvdvb param: 'l',process: 'Vds=1.0V'
  vths["meas"] = true
  mf.jtable[1]["VTH_L"] << vths
  mf.copy_graph "measdata","Vds_1"
  mf.jtable[1]["measdata"] = []
  #mf.copy_graph "Vds0_05","measdata",true  
  mf.jtable[0]["basename"] = "nmos_id_vgs"
  mf.jtable[0]["dir"]      = params[:wdir] + "json/"
  mf.jtable[0]["step"]     ='STEP3'

  mf.write_json
  mf.plot_graph "Vds0_05"
  mf.plot_graph "Vds_1"
  mf.plot_graph "VTH_L"
  
  ### Calc Rds-L Curve
  mf.copy_graph "Vds0_05","measdata",true
  #mf.step3_transform_id_vgs_to_rd_l from: 3.0,to:5.0
  mf.jtable[1]["measdata"].delete_at(0)
  #  mf.jtable[1]["measdata"].delete_at(0)

  mf.step3_estimate_lint_rdsw step: 0.5,from:1.0, to: 5.0
  mf.step3_estimate_lint_rdsw2 from:1.0, to: 5.0

  mf.jtable[1]["delta_vth"] = []
  mf.jtable[1]["delta_vth"] = mf.step6_get_delta_vth "VTH_L"

  ori  = []
  ori  << mf.jtable[1]["delta_vth"][2]
  calc = mf.step6_calculate_dsub_eta0 ddata: ori ,vds: 0.95,vbs: 0,dsub: 0.56,eta0: 0.08,etab: 0.0,w: 60e-6
  mf.jtable[0]["step"] = 'STEP6'
  mf.jtable[1]["plotdata"] = calc
  mf.jtable[1]["measdata"] = ori
  mf.write_json
  mf.plot_graph "delta_vth"

  ### [STEP6-4] Estimate Dsub & Eta0 ###
  #ori.delete_at(1)
  #ori[0]["y"].delete_at(0)
  mf.step6_estimate_dsub_eta0 ori: ori
  dsub = (mf.model.get :DSUB).to_f
  eta0 = (mf.model.get :ETA0).to_f
  calc = mf.step6_calculate_dsub_eta0 ddata: ori ,vds: 0.05,vbs: 0,dsub: dsub,eta0: eta0,etab: 0.0,w: 60e-6
  calc[0]["name"] = '[D2] @Vds=0.05V'
  calc[0]['meas'] = false
  mf.jtable[1]["DSUB_ETA0"] << calc[0]
  mf.plot_graph "DSUB_ETA0"
  mf.write_json

  ### [STEP6-5] Caliculate VTH[4] ###
  ori  = []
  ori  << mf.jtable[1]["delta_vth"][0]
  dvt0 = (mf.model.get :DVT0).to_f
  dvt1 = (mf.model.get :DVT1).to_f
  #dvt0 =0.3
  #dvt1 = 1.02
  calc = mf.step6_calculate_dvt0_dvt1 ddata: ori ,vds: 0.05,vbs: 0,dvt0: dvt0,dvt1: dvt1,dvt2: -0.032,w: 60e-6
  mf.jtable[0]["step"] = 'STEP6-5'
  mf.jtable[1]["plotdata"] = calc
  mf.jtable[1]["measdata"] = ori
  mf.write_json

  ### [STE6-6] Estimate DVT0 & DVT1  ###
  #ori[0]["x"].delete_at(0)
  #ori[0]["y"].delete_at(0)
  mf.step6_estimate_dvt0_dvt1 ori: ori
  dvt0 = (mf.model.get :DVT0).to_f
  dvt1 = (mf.model.get :DVT1).to_f
  calc = mf.step6_calculate_dvt0_dvt1 ddata: ori ,vds: 0.05,vbs: 0,dvt0: dvt0,dvt1: dvt1,dvt2: -0.032,w: 60e-6

  calc[0]["name"] = '[D4] @Vds=0.05V'
  calc[0]['meas'] = false

  mf.jtable[1]["DVT0_DVT1"] << calc[0]
  mf.plot_graph "DVT0_DVT1"
  mf.write_json
  
  
=end
  ### [STEP6-7] Id-Vgs analysys ####
=begin
  ### Bsim3Fit Class Create
  #mf = Bsim3Fit.new params[:model], params[:model_org]
  ori_file ="Id_Vgs_L_0_05.json"
  mf.read_table [params[:wdir] , "json",ori_file].join("/")
  mf.data_cut num: 51          # data cut
  p mf.list_graph
  mf.jtable[0]["step"] = "STEP6-6"
  mf.write_json
  mf.copy_graph "plotdata","measdata",true
  mf.calculate_vth_vbs_relation flg: false, vgs: 0.0, vds: 0.05, vbs: 0.0, lw: [[3e-6,60e-6],[4e-6,60e-6],[5e-6,60e-6],[6e-6,60e-6],[10e-6,60e-6]], mode: "lines",name: params[:lname] 
  p mf.print_condition
  vths = mf.convert_vth_lwvdvb param: 'l',process: 'Vds=50mV'
  vths["meas"] = false
  mf.jtable[1]["VTH_L"][2] = vths
  mf.save_json
  mf.plot_graph "VTH_L"



=end
  ### ??? ###
=begin    
    ## Calculate Vth,avg,stdv
    mf.copy_graph "Vds0_05","measdata",true       #"Vds0_05" =>"measdata" to calculate VTH
    ### Check graph name
    for i in 0..mf.jtable[1]["measdata"].size - 1 do
      p "name(#{i}) = #{mf.jtable[1]["measdata"][i]["name"]}"
    end
    mf.calculate_vth_vbs_relation flg: false, vgs: 0.0, vds: 0.05, vbs: [0,1,2] #,mode: "lines", lw: [6e-6,12e-6] #, name: ["0","1","2","3","4","5","6","7","8"]
    #mf.set_condition l:6e-6,w:12e-6
    mf.print_condition
    data =(mf.convert_vth_lwvdvb param: "vbs",process: "ICPS").dup   # create VTH-Vbs(dummy)curve
    data["name"] = "Vds=0.05V"
    mf.jtable[1]["vth"] << data          #insert data to "vth" @vds=0.05V

    #calc avg & STDV
    datav = mf.duplicate_j_data         #initialize data datav {....} for avg & stdv
    #datav = mf.duplicate_hash mf.duplicate_j_data
    datav["meas"] = false               #set plotdata Mode
    datav["x"] = data["x"].dup          #copy "x"
    imax  = data["x"].size - 1
    #datav["y"] = data["y"].dup          #copy "y"
    dd         = mf.calc_avg_stdv data = data["y"].dup  #get dd["avg","stdv"]
    avg  = dd["avg"]
    stdv = dd["stdv"]
    #p " avg = #{avg} stdv =#{stdv}" 
    for i in 0..imax do               #make avg curve
      datav["y"][i] = avg             #copy avg to "y"
    end
    datav["name"] = "Vds=0.05 avg(#{avg}),stdv(#{stdv})"
    mf.jtable[1]["vth"] << datav.dup  #insert datav(avg & stdv) to "vth"
=end
=begin    
    ### create VTH - avg graph
    datadv = mf.duplicate_hash datav                 #copy data to datadv(vth-avg)
    datadv["y"] = [].dup
    datadv["name"] ="VTH-AVG(vds=0.05)"
    for i in 0..imax do               #cal vth - avg
      datadv["y"][i] = data[i] - avg
    end
    datadv["avg"]  = avg
    datadv["stdv"] = stdv
    datadv["meas"] = false
    mf.jtable[1]["vth"] << datadv.dup  #insert datadv(vth - avg) to "vth"
=end
=begin
    # calc Vds_1
    mf.copy_graph "Vds_1","measdata",true
    mf.calculate_vth_vbs_relation flg: false, vgs: 0.0, vds: 1.0, vbs: [0,1,2],mode: "lines", lw: [6e-6,12e-6] #, name: ["0","1","2","3","4","5","6","7","8"]
    #mf.set_condition l:6e-6,w:12e-6
    mf.print_condition
    data =(mf.convert_vth_lwvdvb param: "vbs",process: "ICPS").dup  # create VTH-Vbs(dummy)curve
    data["name"] = "Vds=1.0V"
    mf.jtable[1]["vth"] << data     #insert data to "vth" @vds=1.0V
    
    #clc avg & STDV
    datav = mf.duplicate_j_data
    datav["meas"] = false          #set plotdata Mode
    datav["x"] = data["x"].dup
    imax  = data["x"].size - 1
    dd         = mf.calc_avg_stdv data = data["y"].dup
    avg  = dd["avg"]
    stdv = dd["stdv"]
    
    for i in 0..imax do
      datav["y"][i] = avg
    end
    datav["name"] = "Vds=1.0 avg(#{avg}),stdv(#{stdv})"
    mf.jtable[1]["vth"] << datav      #insert datav(avg & stdv)
=end
=begin
    ### create VTH - avg graph
    datadv = mf.duplicate_hash datav                 #copy data to datadv(vth-avg)
    datadv["y"] = [].dup
    datadv["name"] ="VTH-AVG(vds=0.05)"
    for i in 0..imax do               #cal vth - avg
      datadv["y"][i] = data[i] - avg
    end
    datadv["avg"]  = avg
    datadv["stdv"] = stdv
    datadv["meas"] = false
    mf.jtable[1]["vth"] << datadv.dup  #insert datadv(vth - avg) to "vth"
=end
  

  ### ModelPrameters for Vth ###
=begin
  ### lists is for Array(csv file) of model parameters ###
  lists =[" process,tox,nch,nsub,lint,wint,vth0,nlx,k1, k2, k3,k3b,w0,dvt0,dvt1,dvt2,dsub,eta0,etab,dvt0w,dvt1w,dvt2w,phis,vbi,vbi2,xdep,xdep0,lt,lt0,ltw" ]

  ### get spice parameters from some processes
  files.each { |m|
    m_process = m["process"]
    m_model   = m["model"]
    m_size    = m["size"]
    m_lw      = m["lw"]
    m_name    = m["name"]
    m_table   = m["jtable"]
    m_num     = m["num"]

    p "#{m_table} is #{FileTest.exist?("json/original/" + m_table)}"
    ### modeel parameters list create (sucsessfully!!)
    mdl = CompactModel::new m_model  
    mdl_list = mf.step0_get_vth_param mdl , m,vbs:0.0
    lists << mdl_list.dup
  }   
  ### write CSV file 
  File.open("csv/VTH_model.csv", "w") do |f|
    lists.each { |s| f.puts(s) }
  end
=end

  ### Vth-l Curve Mathmatically (Under Constructing)
=begin  
  data = (mf.step0_calculate_vth_l mdl,files[i],vbs: 0.0,vds: 0.05,l: 100e-6,w:100e-6).dup

  mf.jtable[1] = data[1].dup
  #p "mf ftom = #{mf.jtable[0]}"
  #p "J_table = #{J_table[0]}"
 
  mf.jtable[0]["basename"] = "VTH_L"
  mf.jtable[0]["dir"]      ="json/"
  mf.jtable[0]["device"]   = files[i]["process"] 
 
  mf.write_json 
  #p mf.jtable[1]["measdata"]


  ###  PTS06 Vth-L Curve

  mf1 = Bsim3Fit.new params[:model_org], params[:model_org]
  ### [STEP0]::Id-Vgs Curve Reads ###
  mf1.imitate_measdata File.join(params[:wdir], params[:jtable_pts])
=end

  ### Vth-L Curve from simulation
=begin  
  files.each { |m|
    m_process = m["process"]
    m_model   = m["model"]
    m_size    = m["size"]
    m_lw      = m["lw"]
    m_name    = m["name"]
    m_table   = m["jtable"]
    m_num     = m["num"]

    mdl = CompactModel::new m_model
    vth0  = (mdl.get :VTH0).to_f
    p "process =#{m_process}  vth0 = #{vth0}  Number of data =#{m_num}"
    mf.jtable[1]["plotdata"] = []   # data Iitiialized ["plotdata"]
    mf.jtable[1]["measdata"] = []   # data Initialized ["measdata"]
    if !FileTest.exist?("json/" + m_table) then 
      mf.imitate_measdata File.join("json/original", m_table)     # data read
      mf.data_cut num: m_num          # data cut
      mf.jtable[0]["basname"] = File.basename(m_name,".json")
      p "process = #{m_process} basename = #{mf.jtable[0]["basename"]} dir = #{mf.jtable[0]["dir"]} Num of Data = #{mf.jtable[1]["measdata"][0].size}"
      mf.save_json       ### save json/[process]_meas.json
    else
      mf.imitate_measdata File.join("json", m_table)     # data read
    end
    mf.jtable[0]["basename"] = File.basename(m_table,".json") 
    mf.jtable[0]["dir"]      = "json/"
    mf.jtable[0]["device"]   = m_process 
    mf.jtable[0]["ver"]      = 1.0
    
    p "device = #{m_process}  => num of lw =#{m_lw.size} num of name = #{m_name.size} num of curve = #{mf.jtable[1]["measdata"].size}"
        
    ### [STEP1]:: VTH[V Calculation ( Vs. L)  for some process
    mf.calculate_vth_vbs_relation flg: false, vgs: 0.0, vds: 0.05, vbs: 0.0,mode: "lines", lw:   m_lw , name: m_name
    mf.print_condition

    data = (mf.convert_vth_lwvdvb param: "l",process: m_process).dup #VTH-L Curves
    imax = data["y"].size - 1
    vmax = data["y"][imax].dup
    delta = data.dup
    zdata = data.dup
    data["name"] = data["name"]   + "(#{vth0.round(3)})".dup
    delta["y"] = []
    delta["name"] = delta["name"] + "(#{vth0.round(3)})".dup
    zdata["y"] = []
    zdata["name"] = zdata["name"] + "(#{vmax.round(3)})".dup

    #Delta-VTH_L Curves
    # change vth => (vth - vth0)
    p "process = #{data["name"]} , imax =#{imax},vmax = #{vmax},  vth0 =#{vth0}"
    for i in 0..imax do
      delta["y"][i] = data["y"][i] - vth0
      zdata["y"][i] = data["y"][i] - vmax
    end

    p "process = #{m_process}  name = #{data["name"]}"
    #p data
    mf.jtable[1]["VTH_L"] << data.dup
    mf.jtable[1]["delta_vth"] << delta.dup
    mf.jtable[1]["zero_vth"]  << zdata.dup
    p " process = #{m_process} ,n= #{mf.jtable[1]["VTH_L"].size}"
  }

  for i in 0..mf.jtable[1]["measdata"].size - 1 do
    p " @jtable[1][measdata][#{i}][name] = #{mf.jtable[1]["measdata"][i]["name"]}"
  end  

  #write whole graph
  mf.jtable[0]["basename"] = "VTH_L_ALL"  
  mf.jtable[0]["dir"]      = "json/"
  mf.jtable[0]["device"]   = "ALL" 
  mf.write_json

  mf.plot_graph "VTH_L"
  mf.jtable[0]["basename"] = "VTH_L_ALL"  
  mf.jtable[0]["dir"]      = "json/"
  mf.jtable[0]["device"]   = "vth-l" 
  mf.write_json

  mf.plot_graph "delta_vth"
  #mf.jtable[0]["basename"] = "deltaVTH_L"  
  #mf.jtable[0]["dir"]      = "json/"
  #mf.jtable[0]["device"]   = "process" 
  
  mf.plot_graph "zero_vth"
  #mf.jtable[0]["basename"] = "zeroVTH_L"
  #=end

  ### standard deviation
  ##=begin
  mf.copy_graph "zero_vth" ,"stdv_vth" , true
  meas = mf.jtable[1]["stdv_vth"]
  for i in 0..meas.size - 1 do
    meas[i]["meas"] = true
  end

  ### setup avg & stdv graphs
  meas << mf.duplicate_j_data   # for avg  meas[ii-1]
  meas << mf.duplicate_j_data   # for stdv meas[ii]
  ii = meas.size - 1
  meas[ii - 1]["name"] ="avg"
  meas[ii - 1]["meas"] =false
  meas[ii]["name"] ="stdv"
  meas[ii]["meas"] =false


  stddata = {"x"=>0,"y"=>[],"avg"=> 0,"std"=>0}
  stdlist =[]
  xdata = [1e-6,2e-6,4e-6,10e-6,20e-6,40e-6,100e-6]
  meas[ii - 1]["x"] = xdata.dup
  meas[ii]["x"]     = xdata.dup

  jmax = meas.size - 3
  imax = xdata.size - 1
  for i in 0..imax do #L-change
    stddata["x"] = xdata[i]    #insert xdata[i] to stddata ["x"] 
    stddata["y"] = [] #initialize stddata["y"]
    for j in 0..jmax do
      if (ij = meas[j]["x"].index(xdata[i]))  then # if meas[j]["x"] in xdata[i] 
        stddata["y"] << meas[j]["y"][ij]
      end
    end
    p " i = #{i} L = #{stddata["x"]}, vth = #{stddata["y"]} "
    #    p stddata
    mean =  stddata["y"].sum/stddata["y"].size
    stds =  stddata["y"].map{|x| ((x - mean)**2)}.sum
    stdv =  Math.sqrt(stds/stddata["y"].size)
    stddata["avg"] = mean
    stddata["std"] = stdv
    stdlist << stddata.dup
  end
  p stdlist
  i_avg  = ii-1  #for avg
  i_stdv = ii    #for stdv
  meas[i_avg]["x"]       = xdata.dup
  for i in 0..imax do
    meas[i_avg]["y"][i]  = stdlist[i]["avg"]
  end

  meas[i_stdv]["x"]      = xdata.dup
  for i in 0..imax do
    meas[i_stdv]["y"][i] = stdlist[i]["std"]
  end
  mf.write_json
  mf.plot_graph "stdv_vth"
=end


  ### VTH_W Simulation
=begin  
  mf.jtable[1]["vth_w"]       = []
  mf.jtable[1]["delta_vth_w"] = []
  mf.jtable[1]["zero_vth_w"]  = []
  mf.jtable[1]["stdv_vth_w"]  = []
  mf.jtable[1]["calc_vth_w"]  = []

  mf.jtable[0]["basename"] = "VTH_W"  
  mf.jtable[0]["dir"]      = "json/"
  mf.jtable[0]["device"]   = "" 
  mf.jtable[0]["ext"]      = "json"

  files = [{"process"=>"DEFAULT",  "model"=> params[:model_def] ,  "jtable"=>params[:jtable_def_w], "size"=> 1.0e-6,"num"=> 501,
             "lw"=>params[:ww],"name"=> params[:wname]},
           {"process"=>"PTS06",   "model"=> params[:model_pts] ,  "jtable"=>params[:jtable_pts_w], "size"=> 0.6e-6,"num"=> 501,
             "lw"=>params[:ww],"name"=> params[:wname]},
           {"process"=>"ICPS",    "model"=> params[:model_icps] , "jtable"=>params[:jtable_icps_w], "size"=> 1.0e-6,"num"=> 501,

           "lw"=>params[:ww],"name"=> params[:wname]},
           {"process"=>"Citizn",  "model"=> params[:model_ctzn] , "jtable"=>params[:jtable_ctzn_w], "size"=> 0.35e-6,"num"=> 501,
             "lw"=>params[:ww],"name"=> params[:wname]},
           {"process"=>"tias130", "model"=> params[:model_tias] , "jtable"=>params[:jtable_tias_w],  "size"=> 0.13e-6,"num"=> 301,
             "lw"=>params[:ww],"name"=> params[:wname]}]

  # Data read and calicurate VTH routine
  files.each { |m|
    m_process = m["process"]
    m_model   = m["model"]
    m_size    = m["size"]
    m_lw      = m["lw"]
    m_name    = m["name"]
    m_table   = m["jtable"]
    m_num     = m["num"]

    mdl = CompactModel::new m_model
    vth0  = (mdl.get :VTH0).to_f
    p "process =#{m_process}  vth0 = #{vth0}  model =#{m_model}"

    mf.jtable[1]["plotdata"] = []   # data Iitiialized ["plotdata"]
    mf.jtable[1]["measdata"] = []   # data Initialized ["measdata"]
    mf.jtable[0]["basename"] = File.basename(m_table,".json")  
    mf.jtable[0]["dir"]      = "json/"
    mf.jtable[0]["device"]   = "" 
    if !FileTest.exist?("json/" + m_table) then 
      ### if measurement data is not in json/ create json/original_data
      p "There is not data json/#{m_table}. Create #{File.join("json/original", m_table)}"
      mf.imitate_measdata File.join("json/original", m_table)     # data read
      mf.data_cut num: m_num          # data cut
      mf.jtable[0]["basname"] = File.basename(m_table,".json")
      p "process = #{m_process} basename = #{mf.jtable[0]["basename"]} dir = #{mf.jtable[0]["dir"]} Num of Graphs = #{mf.jtable[1]["measdata"].size}"
      mf.jtable[0]["basename"] = File.basename(m_table,".json")  
      mf.save_json       ### save json/[process]_meas.json
    else
      p "There is json/#{m_table}. Read this file."
      mf.imitate_measdata File.join("json", m_table)     # data read
    end
    
    mf.jtable[0]["basename"] = "VTH_W" 
    mf.jtable[0]["dir"]      = "json/"
    mf.jtable[0]["device"]   = "" 
    mf.jtable[0]["ver"]      = 1.0
        
    p "device = #{m_process}  => num of lw =#{m_lw.size} num of name = #{m_name.size} num of curve = #{mf.jtable[1]["measdata"].size}"
        
    ### [STEP1]:: VTH Calculation ( Vs. w)  for some process
    mf.calculate_vth_vbs_relation flg: false, vgs: 0.0, vds: 0.05, vbs: 0.0,mode: "lines", lw:   m_lw , name: m_name
    mf.print_condition

    data = (mf.convert_vth_lwvdvb param: "w",process: m_process).dup #VTH-W Curves
    imax = data["y"].size - 1
    vmax = data["y"][imax].dup
    delta = data.dup
    zdata = data.dup
    data["name"] =data["name"] + "(#{vth0.round(3)})".dup
    delta["y"] = []
    delta["name"] =delta["name"] + "(#{vth0.round(3)})".dup
    zdata["y"] = []
    zdata["name"] =zdata["name"] + "(#{vmax.round(3)})".dup

    #Delta-VTH_w Curves
    # change vth => (vth - vth0)
    p "process = #{data["name"]} , imax =#{imax},vmax = #{vmax}"
    for i in 0..imax do
      delta["y"][i] = data["y"][i] - vth0
      zdata["y"][i] = data["y"][i] - vmax
    end

    p "process = #{m_process}  name = #{data["name"]}"
    #p data
    mf.jtable[1]["vth_w"] << data.dup
    mf.jtable[1]["delta_vth_w"] << delta.dup
    mf.jtable[1]["zero_vth_w"]  << zdata.dup
    p " process = #{m_process} , #{mf.jtable[1]["vth_w"].size}"
  }

  for i in 0..mf.jtable[1]["measdata"].size - 1 do
    p " @jtable[1][measdata][#{i}][name] = #{mf.jtable[1]["measdata"][i]["name"]}"
  end  
  mf.jtable[0]["device"]  = "ALL"
  mf.write_json

  mf.plot_graph "vth_w"
  mf.plot_graph "delta_vth_w"
  mf.plot_graph "zero_vth_w"
 
  ### standard deviation

  mf.copy_graph "zero_vth_w" ,"stdv_vth_w" , true
  meas = mf.jtable[1]["stdv_vth_w"]
  for i in 0..meas.size - 1 do
    meas[i]["meas"] = true
  end

  ### setup avg & stdv graphs
  meas << mf.duplicate_j_data   # for avg  meas[ii-1]
  meas << mf.duplicate_j_data   # for stdv meas[ii]
  ii = meas.size - 1
  meas[ii - 1]["name"] ="avg"
  meas[ii - 1]["meas"] =false
  meas[ii]["name"] ="stdv"
  meas[ii]["meas"] =false


  stddata = {"x"=>0,"y"=>[],"avg"=> 0,"std"=>0}
  stdlist =[]
  xdata = [1e-6,2e-6,4e-6,10e-6,20e-6,40e-6,100e-6]
  meas[ii - 1]["x"] = xdata.dup
  meas[ii]["x"]     = xdata.dup

  jmax = meas.size - 3
  imax = xdata.size - 1
  for i in 0..imax do #L-change
    stddata["x"] = xdata[i]    #insert xdata[i] to stddata ["x"] 
    stddata["y"] = [] #initialize stddata["y"]
    for j in 0..jmax do
      if (ij = meas[j]["x"].index(xdata[i]))  then # if meas[j]["x"] in xdata[i] 
        stddata["y"] << meas[j]["y"][ij]
      end
    end
    p " i = #{i} W = #{stddata["x"]}, vth = #{stddata["y"]} "
    mean =  stddata["y"].sum/stddata["y"].size
    stds =  stddata["y"].map{|x| ((x - mean)**2)}.sum
    stdv =  Math.sqrt(stds/stddata["y"].size)
    stddata["avg"] = mean
    stddata["std"] = stdv
    stdlist << stddata.dup
  end
  
  i_avg  = ii-1  #for avg
  i_stdv = ii    #for stdv
  meas[i_avg]["x"]       = xdata.dup
  for i in 0..imax do
    meas[i_avg]["y"][i]  = stdlist[i]["avg"]
  end

  meas[i_stdv]["x"]      = xdata.dup
  for i in 0..imax do
    meas[i_stdv]["y"][i] = stdlist[i]["std"]
  end
  mf.write_json
  mf.plot_graph "stdv_vth_w"

  ### caliculate VTH - W  ####
  mf.copy_graph "zero_vth_w","calc_vth_w"

  files.each { |m|
    m_process = m["process"]
    m_model   = m["model"]
    m_size    = m["size"]
    m_lw      = m["lw"]
    m_name    = m["name"]
    m_table   = m["jtable"]
    m_num     = m["num"]

    mdl = CompactModel::new m_model
    vth0  = (mdl.get :VTH0).to_f
    p "process =#{m_process}  vth0 = #{vth0}  Number of data =#{m_num}"
    tox = (mdl.get :TOX).to_f
    k3  = (mdl.get :K3).to_f
    w0 = (mdl.get :W0).to_f
    if (mdl.get:NSUB).nil? then
      nsub   =  6.0E16
    else
      nsub   =  (mdl.get:NSUB).to_f
    end
    phis  = 2.0*Vt*Math.log(nsub/Ni)
    p "model = #{m_model} , phis = #{phis}"
    xdata = [1e-6,2e-6,4e-6,10e-6,20e-6,40e-6,100e-6]
    ddata  = mf.duplicate_j_data
    ddata["meas"] = false
    ddata["name"] = "#{m_process}(calc)"
    for i in 0..xdata.size - 1 do
      ddata["x"][i] = xdata[i].dup
      xw = xdata[i]
      ddata["y"][i] = k3 * tox/(xw + w0) * phis
    end
    p "procss =#{m_process} ,data =#{ddata["y"]}"
    #p ddata
    mf.jtable[1]["calc_vth_w"] << ddata.dup
  }
  mf.write_json
  mf.plot_graph "calc_vth_w"
=end

=begin
  mf.step1_estimate_vth_k1_k2
  mf.step1_calc_vth_vbs
  mf.plot_graph "vthdata"
=end
end
