$:.unshift File.dirname(__FILE__)
$:.unshift File.join(File.dirname(__FILE__), '../ade_express')
$:.unshift './ade_express'
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
if RUBY_VERSION < '3.0'
  require 'ngspice'
  require 'ngspctl'
end
require 'qucsctl'
