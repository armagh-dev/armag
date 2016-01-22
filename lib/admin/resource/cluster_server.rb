require_relative '../../connection'

module Armagh
  module Admin
    module Resource
    
      class ClusterServer
      
        def initialize( ip )
          @ip = ip
        end
      
        def profile
        
          profile = {
            cpus:    `cat /proc/cpuinfo | grep processor | wc -l `.strip.to_i,
            ram:     `cat /proc/meminfo | awk '/MemTotal/{ print $2}'`.strip.to_i * 1024,
            swap:    `swapon -s | awk 'NR==2 { print $3 }'`.strip.to_i,
            os:      `uname -a`,
            ruby_v:  `ruby -v 2>/dev/null`,
            armagh_v: `gem list 2>/dev/null | grep armagh`,
            disks:    {}
          }
        
          [ 'ARMAGH_DATA', 'ARMAGH_DB_INDEX', 'ARMAGH_DB_LOG', 'ARMAGH_DB_JOURNAL' ].each do |env_var|
            df_info = `df -TPB 1 $#{env_var} 2>/dev/null | awk 'NR==2 { print }'` || ''
            dir=ENV[ env_var ]
            filesystem_name,
            filesystem_type,
            blocks,
            used,
            available,
            use_perc,
            mounted_on = df_info.split( /\s+/ )
            profile[ :disks ][ env_var ] = {
              
              dir: dir,
              filesystem_name: filesystem_name,
              filesystem_type: filesystem_type,
              blocks: blocks.to_i,
              user: used.to_i,
              available: available.to_i,
              use_perc: use_perc.to_i,
              mounted_on: mounted_on
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