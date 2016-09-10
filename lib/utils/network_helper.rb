# Copyright 2016 Noragh Analytics, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.
#

require_relative '../logging'
require_relative '../errors'

require 'socket'
require 'resolv'
require 'ipaddr'

module Armagh
  module Utils
    class NetworkHelper
      def self.local_ip_addresses
        Socket.ip_address_list.collect{|ip| IPAddr.new(ip.ip_address.sub(/%.*/, ''))}
      end

      def self.local?(host)
        if ((host =~ Resolv::IPv4::Regex) || (host =~ Resolv::IPv6::Regex))
          # Ip address
          return true if host.start_with? '127.'
          ip_address = IPAddr.new(host)
          return true if ip_address == IPAddr.new('0.0.0.0') || ip_address == IPAddr.new('::')

          local_ip_addresses.each {|ip| return true if ip_address == ip}
        else
          # hostname
          return true if host == Socket.gethostname
          resolved_addresses = Resolv.getaddresses(host).collect{|addr| IPAddr.new(addr.gsub(/\%.+$/,''))}
          return !(local_ip_addresses & resolved_addresses).empty?
        end
        false
      end
    end
  end
end