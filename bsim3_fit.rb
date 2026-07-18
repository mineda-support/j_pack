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

J_data  = {"x" => [],"y" => [],"z" => [],"vgs"=> 0.0,"vds"=>0.0,"vbs" =>0.0,"vth" =>0.0,"l"=>0.0,"w"=>0.0,"gmax"=>[],"name" =>"","mode" =>"lines","meas"=>true,"sweep" =>"vgs"} unless defined? J_data
#J_table = [{"plot_number"=>0,"title"=>[],"title_x"=>[],"title_y"=>[],"xaxis_is_log"=> [],"yaxis_is_log"=> [],"day"=> "","basename"=> "","filename" => "","ver"=>0.99,"act"=> " ","device"=> "","dir"=>"json/","ext"=> "json","step"=> ""},{},{}] unless defined? J_table
J_table = [{"plot_number"=>0,"title"=>[],"title_x"=>[],"title_y"=>[],"xaxis_is_log"=> [],"yaxis_is_log"=> [],"day"=> "","basename"=> "","filename" => "","ver"=>0.99,"act"=> " ","device"=> "","dir"=>"json/","ext"=> "json","step"=> ""},{"plotdata"=> [],"measdata"=> []}] unless defined? J_table
### xls file read point ###
M_IdVgs = [{ "vgs"=> 'H' ,"ids"=>'A',"vds"=>'B'},
           { "vgs"=> 'S' ,"ids"=>'L',"vds"=>'M'},
           { "vgs"=> 'AD',"ids"=>'W',"vds"=>'X' } ]

M_IdVds = [{ "ids"=> 'Q' ,"vds"=>'R',"vgs"=>'X'},
           { "ids"=> 'Y' ,"vds"=>'Z',"vgs"=>'AF'},
           { "ids"=> 'AG' ,"vds"=>'AH',"vgs"=>'AN'},
           { "ids"=> 'AO' ,"vds"=>'AP',"vgs"=>'AV'},
           { "ids"=> 'AW' ,"vds"=>'AX',"vgs"=>'BD'} ]
       


class ModelFit
  attr_accessor :model, :model_org, :jtable, :phis,:vbi
  def initialize model="models/test.lib", model_org="models/MinedaPTS06_TT"
    @model     = CompactModel::new model
    @model_org = CompactModel::new model_org
    @jtable    = duplication_j_table 
    nsub = get_nsub
    @phis = 2.0*Vt*Math.log(nsub/Ni)
    nch = (@model.get :NCH).to_f
    @vbi   = Vt * Math.log(nch  * NDS / (Ni**2))
  
  end

  # define NSUB
  def get_nsub
    nch_cm = (@model.get :NCH).to_f      # [cm^-3]
    tox    = (@model.get :TOX).to_f      # [m]
    k1     = (@model.get :K1 ).to_f

    nch    = nch_cm * 1.0e6              # [m^-3] に変換

    eps_si = ESi * E0                    # 比誘電率 × ε0 → [F/m]
    cox    = Eox * E0 / tox              # [F/m^2]

    gamma1 = Math.sqrt(2 * Q * eps_si * nch) / cox

    nsub_m3 = ((gamma1 - k1) * cox)**2 / (2 * Q * eps_si)
    nsub_cm3 = sig_round(nsub_m3 / 1.0e6,4)           # [cm^-3] に戻す

    #p "nch_cm=#{nch_cm} tox=#{tox} K1=#{k1} gamma1=#{gamma1} nsub_cm3=#{nsub_cm3}"
    @model.set :NSUB => nsub_cm3
    @model.save
    @phis = 2.0*Vt*Math.log(nsub_cm3/Ni)

    return nsub_cm3
  end

  # 有効数字 N 桁丸め
  def sig_round(x, n)
    return x if x == 0
    factor = 10 ** (n - 1 - Math.log10(x.abs).floor)
    (x * factor).round / factor.to_f
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
    #p "ver =#{data["ver"]}"
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

  def invert_sign(target: "measdata", keys: ["x", "y"])
    return unless @jtable[1][target].is_a?(Array)
    @jtable[1][target].each do |row|
      keys.each { |key| row[key].map! { |n| -n } }
    end
  end

  def set_data(target: "measdata", type: "sweep", value: nil)
    for i in 0..@Jtable[1][target].size - 1 do
      @Jtable[1][target][i][type] = value
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

  def read_idvds_xls dir: "IdVgs", files:{},graph: "measdata",is_lw: false,l:10e-6,w:60e-6,vbs:0
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

      for i in 0..M_IdVds.size - 1 do
        tmp = duplicate_j_data
        tmp["name"] = dname
        tmp["l"] = dl.round(9)
        tmp["w"] = dw.round(9)
        tmp["vbs"] = 0
        tmp["x"] = sheet.column(M_IdVds[i]["vds"]).dup        #copy vgs
        tmp["x"].shift()
        for j in 0..tmp["x"].size - 1 do
          tmp["x"][j] = tmp["x"][j].to_f #round(4)        #rounding off at 1e-4
        end
        tmp["y"]   = sheet.column(M_IdVds[i]["ids"])          #copy ids
        tmp["y"].shift()
        tmp["vgs"] = sheet.cell(M_IdVds[i]["vgs"],2).to_f #round(3) #rounding off at 1e-3
        tmp["name"] = "Vgs= #{tmp["vgs"].round(1)}V"
        @jtable[1][graph] << tmp.dup
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
    weff   =  w - 2.0 * wint

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
    #weff   =  w - 2.0 * wint

    tox    =  (model.get:TOX).to_f 
    if (model.get:NCH).nil? then
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
  def convert_vth_lwvdvb(target: "measdata",param: "l",process: "PTS06")
    meas = duplicate_j_data
=begin
    @jtable[1][target.each_with_index do |v,i|
      meas["x"][i] = v[param]
      meas["y"][i] = v["vth"]
      meas["l"]     = v["l"]
      meas["w"]     = v["w"]
      meas["vbs"]   = v["vbs"]
      meas["vds"]   = v["vds"]
      meas["name"]  = "sweep #{param}"
      meas["sweep"] = param
      meas["meas"]  = true
      meas[param] = nil
    end
=end
    for i in 0..@jtable[1][target].size - 1 do
      if param == 'i' then
        meas["x"][i] = i
      else
        meas["x"][i] = @jtable[1][target][i][param]
      end
      meas["y"][i] = @jtable[1][target][i]["vth"].round(5)
    end
    meas["l"]     = @jtable[1][target][0]["l"]
    meas["w"]     = @jtable[1][target][0]["w"]
    meas["vbs"]   = @jtable[1][target][0]["vbs"]
    meas["vds"]   = @jtable[1][target][0]["vds"]
    meas["name"]  = "sweep #{param}"
    meas["sweep"] = param
    meas["meas"]  = true
    meas[param] = nil
    return meas
  end


  def print_condition
    #p "filename =  " + @jtable[0]["dir"] + @jtable[0]["basename"] + @jtable[0]["ext"]
    meas =@jtable[1]["measdata"]
    datas =["name","vbs","vgs","vds","vth","l","w","mode","Vgmax","Imax","Gmmax"]
    datas.each{|a| 
      tmp =format("%-8s,",a)
      for i in 0..meas.size - 1 do
        if a == "vth" then
          tmp += format("%-8.4f,",meas[i][a].to_f)
        elsif a =="Vgmax" then
          tmp += format("%-8s,","#{meas[i]["gmax"][0].round(4)}")
        elsif a =="Imax" then
          tmp += format("%-8s,","#{meas[i]["gmax"][1].round(9)}")
        elsif a =="Gmmax" then
          tmp += format("%-8s,","#{meas[i]["gmax"][2].round(6)}")
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
    ddata = duplicate_hash J_table
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
      data = duplicate_hash(from)
    else
      data  = duplicate_hash(@jtable[1][from])
    end
    return data
  end

  #### (1.5) Hash duplication #####
  def duplicate_hash from 
    Marshal.load(Marshal.dump(from))
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

    @jtable[1][dist] = duplicate_data(source)     #@jtable[1][source]
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
    tt = duplicate_data(target)
    @jtable[1][target] = tt + ss
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
    #@jtable[0] = duplicate_head
    #@jtable[0]["basename"] = File.basename(json_file,".json")
    #@jtable[0]["ver"] = 0.99
    #write_json @jtable
  end

  # [STEP-1-1]
  def read_table_all json_file
    if !File.exist?(json_file) then
      p "File::#{json_file} is not exist!!"
      return
    end
    p "json_file =#{json_file} " #, @jtanle[0] = #{@jtable[0]}"
    tmp = (read_json json_file).dup
    @jtable[1] = tmp[1].dup
    
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
  def calculate_vth_vbs_relation(target: "measdata", flg: false, vgs: 0.0, vds: 0.05, vbs: [0.0, -0.5 , -1.0, -1.5,-2.0], lw: [[30e-6,30e-6]], mode: "lines",name: ["l=3u","l=4u","l=5u","l=6u","l=10u"])
    
    meas = @jtable[1][target]
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
    get_params_all
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
    weff   =  w - 2.0 * wint
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
  def step2_calculate_ueff_vgs_relation mag: 0.9, ismax: false
    
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
      gmax = id[i]["gmax"][2].dup
      ii   = id[i]["x"].index{|v| v>=vgm} 
      #p "i = #{ii} Xgmax =#{vgm}  gmax #{gmax}"
      id[i]["x"].slice!(0,ii)
      id[i]["y"].slice!(0,ii)
      id[i]["z"].slice!(0,ii)
      #p "x = #{id[i]["x"][0]}  y =#{id[i]["y"][0]}  z = #{id[i]["z"][0]}"
      ii = id[i]["z"].index{|v| v <= gmax * mag}
      if ismax then
        ik = id[i]["x"].size - 1
      else
        ik   = ii + 10
      end
      p "step2_calculate... vgs_min =#{id[i]["x"][ii]}, Vgs_max =#{id[i]["x"][ik]} mag = #{mag}"
      
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
      #p "gmax =#{gmax} x=#{id[0]["x"]} y = #{id[0]["y"]} z= #{id[0]["z"]}"
    end 
    p "=== end of step2_calculate_ueff_vgs_relation ==="
    return id
  end

  # [STEP2-2] estimation ueff from ueff curve
  def step2_estimation_u0_ua_ub_uc(err: 1e-5,mag: 1.5 ,isvbs: false,ismax:false)

    tox  =(model.get :TOX).to_f
  
    @jtable[0]["step"] = "STEP2" 
    tag = 1.0
    magx = 0.9
    #ismax = false
    
    xy = (step2_calculate_ueff_vgs_relation mag: magx,ismax: ismax).dup
    p "vgs[0] = #{xy[0]["x"][0]}"
    p "ueff[0] = #{xy[0]["z"][0]}"
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
  
    p "cal. error #{((tag * 100).round(12))}% @ mag= #{(magx - 0.01).round(4)}"
    
    if isvbs==false then
      uc = 0.0
      model.set :U0 => (format("%5.5e",u0)).to_f
      model.set :UA => (format("%5.5e",ua)).to_f
      model.set :UB => (format("%5.5e",ub)).to_f
      model.set :UC => (format("%5.5e",uc)).to_f
      model.save
      u0x = "U0 = " + (model.get :U0).to_s
      uax = "UA = " + (model.get :UA).to_s
      ubx = "UB = " + (model.get :UB).to_s
      ucx = "UC = " + (model.get :UC).to_s
      puts "Ueff[SOI]: #{u0x} #{uax} #{ubx} #{ucx}"
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
    puts "Ueff: #{u0x} #{uax} #{ubx} #{ucx}"

    @jtable[0]["act"] =" Estimate Ueff "
  end

  ### verification Ueff(Vgs) ###
  def step2_verification_ueff step: 0.1
    u0  = (@model.get :U0).to_f
    ua  = (@model.get :UA).to_f
    ub  = (@model.get :UB).to_f
    uc  = (@model.get :UC).to_f
    tox = (@model.get :TOX).to_f
    #p [u0,ua,ub,uc,tox]
    ueff = change_step(datas: step2_calculate_ueff_vgs_relation(mag: 1.0, ismax: true),step: step)
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
  #  list_graph
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
  #  [STEP3-0] read Id-Vgs-l data            => imitate_measdata
  #  [STEP3-1] Calculate Vth-l               => calculate_vth_l_relation
  #  [STEP3-2] Transform Id-Vgs-L to Rds-L   => transform_id_vgs_to_rd_l
  #  [STEP3-3] Estimate RDSW & LINT
  #  [STEP3-4] Calculation graphs for verification

    
  ###[STEP3-1] Calculate Vth-l::using calculate_vth_vbs_relation

  def calculate_vth_l_relation flg: false, vgs: 0.0,vds: 0.05,vbs: 0.0,lw: [[0.6e-6,4e-6],[0.8e-6,4e-6],[1.0e-6,4e-6],[1.4e-6,4e-6],[2.0e-6,4e-6]] ,mode: "lines",name: ["l=0.6u","l=0.8u","l=1.0u","l=1.4u","l=2.0u"]

    calculate_vth_vbs_relation flg: flg,vgs: vgs,vds: vds,vbs: vbs,lw: lw,mode: mode,name: name
      
    data0 = @jtable[0]
    #data0["step"]   = "STEP3"
    #data0["act"]    = "STEP3: "
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
      rds_l[i] = duplicate_hash(zz[i])
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
    u0 = (@model.get :U0).to_f
    p "lint_rdsw :: n = #{ii},LINT =#{(x1/2.0).round(12)},RDSW =#{(a_avg * x1 + b_avg).round(2)}, U0 = #{u0},STDV=#{stdv1.round(4)},dx = #{dx.round(16)}"

    @model.set :LINT => (x1/2.0).round(9)
    @model.set :RDSW => (a_avg * x1 + b_avg).round(2)
    @model.save
    get_params_all    


    x0 = (x1).round(9)
    y0 =  (a_avg * x1 + b_avg).round(2)
    data1 = duplicate_j_data
    data1["x"] = [0,x0]
    data1["y"] = [y0,y0]
    @jtable[1]["Rds_L"] << data1
    data2 = duplicate_j_data
    data2["x"] = [x0,x0]
    data2["y"] = [0,y0]
    @jtable[1]["Rds_L"] << data2
    
  end

  #### [STEP4-1] Transform Id-Vgs-L => Gds-W
  def step4_estimate_wint(step: 0.5,flg: false ,from: 3.0, to: 5.0)  
    p [from,to]    
    id   = change_step step: step

    input = id
    vds = input[0]["vds"]

    # W の一覧
    ws = input.map { |e| e["w"] }

    # 元の Vgs 配列
    vgs_all = input.first["x"]

    # 範囲抽出
    vgs_list = vgs_all.select { |v| v >= from && v <= to }

    result = []
    zz = { "x" => [], "y" => [] }

    vgs_list.each do |vgs|
      # ★ 元の Vgs 配列での index を取得（ここが最重要）
      idx = vgs_all.index(vgs)

      # 各 W の y(vgs) を取り出す（正しい Vgs の点）
      y_values = input.map { |entry| entry["y"][idx] }

      rr = duplicate_hash(input[0])
      rr["x"] = ws
      rr["y"] = y_values
      rr["vds"] = vds
      rr["vgs"] = vgs
      rr["sweep"] = "w"
      rr["meas"] = true
      rr["name"] = "vgs=#{vgs}"

      # ここで z を作る
      z = { "x" => rr["x"], "y" => rr["y"] }

      # すべての x,y を zz に追加
      zz["x"] += z["x"]
      zz["y"] += z["y"]

      result << duplicate_hash(rr)
    end

  
    y = determine_1st zz["x"] ,zz["y"]
    # 1次近似結果
    a = y[1]
    b = y[2]

    # WINT
    wint = sig_round(b / (a * 2),4)
    @model.set :WINT => wint
    @model.save
    # プロット用データのテンプレート
    data_a = duplicate_hash(result[0])

    # --- ここが誓さんがやりたい部分 ---
    # Ruby 的に配列の先頭に WINT を追加する
    data_a["x"].unshift(wint)

    # y = a*x + b を計算して新しい y 配列を作る
    data_a["y"] = data_a["x"].map { |x| a*x + b }

    # 追加情報
    data_a["name"]  = "Gds-W linear fit"
    data_a["sweep"] = "w"
    data_a["meas"]  = false   # 計算結果なので meas=false

    p " a=#{a} b=#{b} wint =#{wint}"
    
    @jtable[1]["Gds_W"] =  duplicate_hash(result) 
    @jtable[1]["Gds_W"] << duplicate_hash(data_a)
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
      weff = data[i]["w"] - 2 * wint
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
    weff   =  w - 2.0 * wint
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

  def convert_json_to_data(j_data, file: "data.json", calc_file: "ruby/vth_calc.rb",process:"MinimalFab",optimize:["u0"],bounds:nil,meta:nil)
    entries = j_data.map do |e|
    sweep = e["sweep"]   # "l", "w", "vgs", "vbs", "vds"
    xvals = e["x"]       # sweep 軸の値
    n = xvals.size

    # sweep 軸以外の値を配列化
    w   = sweep == "w"   ? xvals : Array.new(n, e["w"])
    l   = sweep == "l"   ? xvals : Array.new(n, e["l"])
    vgs = sweep == "vgs" ? xvals : Array.new(n, e["vgs"])
    vds = sweep == "vds" ? xvals : Array.new(n, e["vds"])
    vbs = sweep == "vbs" ? xvals : Array.new(n, e["vbs"])
    vth = sweep == "vth" ? xvals : Array.new(n, e["vth"])

    {
      # ★ J_data の name/type をそのまま保存
      "meta"      => meta,
      "process"   => process,
      "name"      => e["name"],
      "type"      => e["type"],
      "sweep"     => e["sweep"],
      # ★ 最適化設定（誓さんが後で編集）
      "optimize"  => optimize,
      "optimizer" => {
        "method" => "Nelder-Mead"
   #     "bounds" => bounds
      },

      # ★ 計算エンジンを引数で指定
      "calc_file" => calc_file,

      # ★ sweep 展開後のデータ
      "l"         => l,
      "w"         => w,
      "vgs"       => vgs,
      "vds"       => vds,
      "vbs"       => vbs,
      "vth"       => vth,

      # ★ 測定値（J_data の y）
      "meas"      => e["y"],
      "calc"      => Array.new(n, 0),
    
      # ★ 重み
      "weights"   => Array.new(n, 1)
    }
    end

    File.write(file, JSON.pretty_generate(entries))
    puts "Converted to #{file}"
    entries
  end

  def calc_l0
    xj  =(@model.get :XJ).to_f
    tox =(@model.get :TOX).to_f
    l0 = Math.sqrt(ESi/Eox * xj * tox)
    return l0
  end

  def get_params_vgid(file:"params_vgid.json")
    u0  =  (@model.get :U0).to_f
    ua  =  (@model.get :UA).to_f
    ub  =  (@model.get :UB).to_f
    uc  =  (@model.get :UC).to_f
    tox =  (@model.get :TOX).to_f
    lint = (@model.get :LINT).to_f
    rdsw = (@model.get :RDSW).to_f
    vsat = (@model.get :VSAT).to_f
    wint = (@model.get :WINT).to_f
    cox = Eox * E0 / tox
    abulk = 1.0
    params =
    {
      "U0" => u0,
      "UA" => ua,
      "UB" => ub,
      "UC" => uc,
      "TOX" => tox,
      "LINT" => lint,
      "RDSW" => rdsw,
      "VSAT" => vsat,
      "WINT" => wint,
      "COX"  => cox,
      "ABULK" => abulk
    }
    File.open(file, "w") do |f|
      f.write(JSON.pretty_generate(params))
    end
    p "params_file to #{file}"
  end

  def get_params_vdid(file:"params_vdid.json")
    tox = (@model.get :TOX).to_f 
    cox = Eox * E0 / tox
    abulk = 1.0
    xdep0 = calc_xdep0
    lt0 = calc_lt0()
    l0  = calc_l0() 
    params =
    {
      "LINT"  => (@model.get :LINT).to_f,
      "RDSW"  => (@model.get :RDSW).to_f,
      "WINT"  => (@model.get :WINT).to_f,
      "U0"    => (@model.get :U0).to_f,
      "UA"    => (@model.get :UA).to_f,
      "UB"    => (@model.get :UB).to_f,
      "UC"    => (@model.get :UC).to_f,
      "VSAT"  => (@model.get :VSAT).to_f,
      "TOX"   => tox,
      "K1"    => (@model.get :K1).to_f,
      "PHI"   =>  @phis,
      "A0"    => (@model.get :A0).to_f,
      "AGS"   => (@model.get :AGS).to_f,      
      "B0"    => (@model.get :B0).to_f,
      "B1"    => (@model.get :B1).to_f,     
      "KETA"  => (@model.get :KETA).to_f,
      "XJ"    => (@model.get :XJ).to_f,     
      "COX"   => cox,
      "XDEP"   => xdep0,
      "PCLM"    => (@model.get :PCLM).to_f,
      "PDIBLC1" => (@model.get :PDIBLC1).to_f,
      "PDIBLC2" => (@model.get :PDIBLC2).to_f,
      "PDIBLCB" => (@model.get :PDIBLCB).to_f,
      "PSCBE1"  => (@model.get :PSCBE1).to_f,
      "PSCBE2"  => (@model.get :PSCBE2).to_f,
      "DROUT"   => (@model.get :DROUT).to_f,
      "PAVG"    => (@model.get :PAVG).to_f,
      "DELTA"   => (@model.get :DELTA).to_f,
      "LT"      => lt0,
      "VT"      => Vt , 
      "ABULK"   => abulk,
      "L0"      => l0
    }
    File.open(file, "w") do |f|
      f.write(JSON.pretty_generate(params))
    end
    p "params_file to #{file}"
  end

  def get_params_sat(file:"params_sat.json")
    tox = (@model.get :TOX).to_f 
    cox = Eox * E0 / tox
    abulk = 1.0
    xdep0 = calc_xdep0
    params =
    {
      "LINT"  => (@model.get :LINT).to_f,
      "PCLM"    => (@model.get :PCLM).to_f,
      "PDIBLC1" => (@model.get :PDIBLC1).to_f,
      "PDIBLC2" => (@model.get :PDIBLC2).to_f,
      "PDIBLCB" => (@model.get :PDIBLCB).to_f,
      "PSCBE1"  => (@model.get :PSCBE1).to_f,
      "PSCBE2"  => (@model.get :PSCBE2).to_f,
      "DROUT"   => (@model.get :DROUT).to_f,
      "PAVG"    => (@model.get :PAVG).to_f,
      "DELTA"   => (@model.get :DELTA).to_f,
      "ABULK" => abulk
    }
    File.open(file, "w") do |f|
      f.write(JSON.pretty_generate(params))
    end
    p "params_file to #{file}"
  end

  def get_params_vth(file:"params_vth.json")
    params = {
      "DVT0W"    => (model.get :DVT0W).to_f,           ##// 幅方向短チャネル効果の強さ
      "DVTNW"    => (model.get :DVT1W).to_f,           ##// 幅方向短チャネル効果の指数減衰係数
      "LNW"      => 1e-7,     ##// 幅方向の特性長（UCB式で使用）
      "VBI"      => @vbi,     ##// 内部電位差 (Vbi - Φs) の基準値
      "PHI"      => @phis,
      "TOX"      => (@model.get :TOX).to_f,
      "NCH"      => (@model.get :NCH).to_f,
      "VTH0"     => (@model.get :VTH0).to_f,
      "K1"       => (@model.get :K1).to_f,
      "K2"       => (@model.get :K2).to_f,
      "DVT0"     => (@model.get :DVT0).to_f,
      "DVT1"     => (@model.get :DVT1).to_f,
      "DVT2"     => (@model.get :DVT2).to_f,
      "LINT"     => (@model.get :LINT).to_f,
      "WINT"     => (@model.get :WINT).to_f,
      "DSUB"     => (@model.get :DSUB).to_f,
      "ETA0"     => (@model.get :ETA0).to_f,
      "ETAB"     => (@model.get :ETAB).to_f,
      "NFACTOR"  => (@model.get :NFACTOR).to_f,
      "NLX"      => (@model.get :NLX).to_f,
      "K3"       => (@model.get :K3).to_f,
      "K3B"      => (@model.get :K3B).to_f,
      "W0"       => (@model.get :W0).to_f,
      "Q"        => Q,
      "E0"       => E0,
      "ESI"      => ESi,
      "Eox"      => Eox,
      "T"        => T,
      "K"        => K,
      "NI"       => Ni,
      "Vt"       => Vt,
      "NDS"      => NDS,
      "ALW"      => 0.0,
      "BL"       => 1.0,
      "BW"       => 1.0,
      "MAG_NLX"  => 1.0,
      "MAG_SCE"  => 0.6887,
      "MAG_SCE2" => 69.242,
      "MAG_DIBL"  => 1.0,
      "MAG_DIBL2" => 1.0,
      "MAG_W"     => 1.0,
      "DELTA_VTH" => 0.0,
      "vth_model" => "ltspice"
    }
    #ltw   = Math.sqrt(ESi * xdep * tox / Eox) * (1.0 + dvt2w * 0.0)
    #p params
    File.open(file, "w") do |f|
      f.write(JSON.pretty_generate(params))
    end
    p "params_file to #{file}"
    params
  end

  def get_params_all
    get_params_vgid
    get_params_vdid
    get_params_vth
    get_params_sat
  end

  def calc_xdep0()
    esi  = ESi    ##params["ESI"]   # シリコン誘電率
    e0   = E0     ##params["E0"]    # 真空誘電率
    phi  = @phis  ##params["PHI"]   # 表面ポテンシャル
    nch  = (@model.get :NCH).to_f   #params["NCH"]   # チャネルドーピング
    q    = Q      ##params["Q"]     # 電荷量

    xdep0 = Math.sqrt(2.0 * esi * e0 * phi / (q * nch))
    return xdep0
  end  

  def calc_lt0()
    esi   = ESi  ##params["ESI"]
    eox   = Eox  ##params["EOX"]
    tox   = (@model.get :TOX).to_f ##params["TOX"]
    xdep0 = calc_xdep0()

    lt0 = Math.sqrt(esi * xdep0 * tox / eox)
    return lt0
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
  
  # Vds-Id の減少領域をカットする
  def cut_decreasing(xs, ys, tol)
    data = xs.zip(ys)
    data.reject! { |x, y| x.nil? || y.nil? }

    cleaned = []
    last_y = -Float::INFINITY
    data.each do |x, y|
      break if y < last_y * (1 - tol)  # tolerance分の減少を許容
      cleaned << [x, y]
      last_y = y
    end
    cleaned
  end


  # measdata を破壊的に書き換える
  def process_measdata!(data,tol)
    data.each do |entry|
      xs = entry["x"]
      ys = entry["y"]
      next unless xs && ys

      cleaned = cut_decreasing(xs, ys,tol)

      # 破壊的に上書き
      entry["x"] = cleaned.map { |p| p[0] }
      entry["y"] = cleaned.map { |p| p[1] }
    end
  end

  ### NULL/NIL data cut
  def clean_data(xs, ys)
  data = xs.zip(ys)
  data.reject! { |x, y| x.nil? || y.nil? }
  cleaned = []
  last_x = -Float::INFINITY
  data.each do |x, y|
    break if x < last_x
    cleaned << [x, y]
    last_x = x
  end
  cleaned
end


end   # end of Bsim3Fit < ModelFit

# ここまでが class Bsim3Fit の定義
# 以降は何も書かない（if $0 == __FILE__ を削除）
