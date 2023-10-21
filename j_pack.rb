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

def create_cdraw
  symbols = Dir.glob("*.asy").map{|a| File.basename(a).sub('.asy','')}
  #puts "symbols: #{symbols.inspect}"
  cells = Dir.glob("*.asc").map{|a| File.basename(a).sub('.asc','')}
  #puts "cells: #{cells.inspect}"
  symbols = symbols - cells
  topcells = cells - symbols
  #puts "topcells: #{topcells.inspect}"
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
