$:.unshift File.dirname(__FILE__)
$:.unshift File.join(File.dirname(__FILE__), './ade_express')
require 'alb_lib'
$:.unshift '.'
require 'compact_model'
require 'lib_util'
require 'ltspice'
require 'postprocess'
require 'qucs'
require 'xschem'
require 'eeschema'
require 'alta'
require 'ltspctl'
require 'ngspice'
require 'ngspctl'
require 'qucsctl'
require 'bsim3_fit'

def create_cdraw
  symbols = Dir.glob("*.asy").map{|a| File.basename(a).sub('.asy','')}
  puts "symbols: #{symbols.inspect}"
  cells = Dir.glob("*.asc").map{|a| File.basename(a).sub('.asc','')}
  puts "cells: #{cells.inspect}"
  topcells = cells - symbols
  puts "topcells: #{topcells.inspect}"
  FileUtils.mkdir 'cdraw' unless File.exist?('cdraw')
  FileUtils.mkdir 'cdraw/symbols' unless File.exist?('cdraw/symbols')
  symbols.each{|sym|
    FileUtils.cp sym+'.asy', File.join('cdraw/symbols', sym+'.asy')
  }
  FileUtils.mkdir 'cdraw/cells' unless File.exist?('cdraw/cells')
  cells.each{|cell|
    FileUtils.cp cell+'.asc', File.join('cdraw/cells', cell+'.asc')
  }
end
if $0 == __FILE__
  #m = CompactModel.new 'MinedaPTS06_TT'
  #puts
  #file = File.join ENV['HOMEPATH'], 'Seafile/PTS06_2023_8/OpAmp8_18/op8_18_tb.asc'
  #file = File.join ENV['HOMEPATH'], 'Seafile/PTS06_2024_8/Op8_18/nch_pch#.asc'
  file = File.join ENV['HOMEPATH'], 'Seafile/LSI開発/PTS06_2023_8/OpAmp8_18/op8_18_tb.asc'
  #file = './j_pack/nch_pch.asc'
  puts Dir.pwd
  ckt = LTspiceControl.new file #, true # test recursive
  ckt.simulate models_update: {"nch":{"VTH0":"0.1624532"}}, 
               variations: {"M1#":["l=0.5u w=10u m=5","l=0.5u w=20u m=5"],
                            "M2#":["l=0.5u w=10u m=10","l=0.5u w=20u m=10"]}
  puts ckt.elements.inspect
  puts ckt.models.inspect
end