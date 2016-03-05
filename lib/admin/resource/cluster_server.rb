require_relative '../../connection'

module Armagh
  module Admin
    module Resource
    
      class ClusterServer

        DEFAULTS = {
            'ARMAGH_DATA' => '/tmp/home/armagh'
        }

        def initialize( ip, logger )
          @ip = ip
          @logger = logger

          begin
            config  = Configuration::FileBasedConfiguration.load('ENV')
          rescue => e
            @logger.error 'Invalid file based configuration for ENV.  Reverting to default.'
            # TODO Split Logging
            @logger.error e
            config = {}
          end

          @config = DEFAULTS.merge config
        end
      
        def profile
          
          os = `uname -a`
          case
          when /Linux/i.match( os ) then linux_profile
          when /Darwin/i.match( os ) then mac_profile
          else {}
          end
        end
        
        def linux_profile
        
          profile = {
            'cpus'     => `cat /proc/cpuinfo | grep processor | wc -l `.strip.to_i,
            'ram'      => `cat /proc/meminfo | awk '/MemTotal/{ print $2}'`.strip.to_i * 1024,
            'swap'     => `swapon -s | awk 'NR==2 { print $3 }'`.strip.to_i,
            'os'       => `uname -a`,
            'ruby_v'   =>  `ruby -v 2>/dev/null`,
            'armagh_v' =>  `gem list 2>/dev/null | grep armagh`,
            'disks'    =>  {}
          }
        
          base_data_dir = @config[ 'ARMAGH_DATA' ]
          [ nil, 'index', 'log', 'journal' ].each do |subdir|
            dir = File.join( base_data_dir, subdir || '')
            df_info = `df -TPB 1 $#{dir} 2>/dev/null | awk 'NR==2 { print }'` || ''
            filesystem_name,
            filesystem_type,
            blocks,
            used,
            available,
            use_perc,
            mounted_on = df_info.split( /\s+/ )
            profile[ 'disks' ][ subdir || 'base' ] = {
              
              'dir'             => dir,
              'filesystem_name' => filesystem_name,
              'filesystem_type' => filesystem_type,
              'blocks'          => blocks.to_i,
              'used'            => used.to_i,
              'available'       => available.to_i,
              'use_perc'        => use_perc.to_i,
              'mounted_on'      => mounted_on
            }
          end
        
          profile
        
        end
        
        def mac_profile
          profile = {
            'cpus'     => `sysctl -n hw.activecpu`.strip.to_i,
            'ram'      => `sysctl -n hw.memsize`.strip.to_i,
            'swap'     => 0,
            'os'       => `uname -a`,
            'ruby_v'   => `ruby -v 2>/dev/null`,
            'armagh_v' => `gem list 2>/dev/null | grep armagh`,
            'disks'    => {}
          }


           base_data_dir = @config['ARMAGH_DATA']

          [ nil, 'index', 'log', 'journal' ].each do |subdir|
            dir = File.join( base_data_dir, subdir || '' )
            df_info = `df $#{dir} 2>/dev/null | awk 'NR==2 { print }'` || ''
            filesystem_name,
            blocks,
            used,
            available,
            use_perc,
            iused,
            ifree, 
            iperc,
            mounted_on = df_info.split( /\s+/ )
            profile[ 'disks' ][ subdir || 'base' ] = {
              
              'dir'             => dir,
              'filesystem_name' => filesystem_name,
              'filesystem_type' => 'mac',
              'blocks'          => blocks.to_i * 512,
              'used'            => used.to_i,
              'available'       => available.to_i,
              'use_perc'        => use_perc.to_i,
              'mounted_on'      => mounted_on
            }
          end
        
          profile
        end          
      
        def evaluate_profile( profile )
          profile
        end
      
        def report_profile( profile )
          Connection.resource_config.find_one_and_update( 
            { _id: @ip }, 
            { '$set' => profile },
            :upsert => true
          )
        end
      
      end
    end
  end
end