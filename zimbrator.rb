#!/usr/bin/env ruby
#
# Code by H3R3T1C (Ing. Luis Felipe Domínguez Vega)
# <ldominguezvega@gmail.com>
#
# For SysAdminsCuba group...

require 'rubygems'
require 'yaml'
require 'net/ssh'
require 'net/ldap'
require 'commander/import'

program :name, 'Zimbra-AD Sync'
program :version, '0.2-alpha'
program :description, 'Simple program to sync the users of Zimbra and the AD'
program :help, 'Author', 'Ing. Luis Felipe Domínguez Vega <ldominguezvega@gmail.com>'

global_option('-c', '--config FILE', 'Configuration file') do |file|
  begin
    puts "[I] Loading config file #{file}"
    @global_config = YAML.load_file(file)
  rescue => e
    puts "[E] Config file error: #{e}"
    exit! 1
  end
end

@yes = false

global_option('-y', '--yes', 'Accept all questions (WARNING)') {@yes = true}

command :remove_from_ad do |c|
  c.syntax = 'zimbrator remove_from_ad'
  c.description = 'List or/and Remove Zimbra users not in AD'

  c.option '--delete', 'Delete users from Zimbra'

  c.action do |args, options|
    if @global_config.nil?
      puts "[E] You must indicate a config file with -c / --config"
      exit! 1
    end

    puts "[I] Mode: #{c.description}"

    puts "[I] Connecting to LDAP server"
    ldap = Net::LDAP.new host: @global_config['ad_host'], port: @global_config['ad_port']

    puts "[I] Authenticating to LDAP server"
    ldap.auth @global_config['ad_user'], @global_config['ad_pass']

    if ldap.bind

      users = []

      puts "[I] Searching for users in LDAP server"
      @global_config['ad_search'].each do |tree_base|
        ldap.search( :base => tree_base ) do |entry|

          user = entry[@global_config['ad_attr']]

          users << user unless user == ''
        end
      end

      puts "[I] Connecting to Zimbra server with SSH"
      Net::SSH.start(@global_config['zimbra_host'], @global_config['zimbra_user'], password: @global_config['zimbra_pass'], port: @global_config['zimbra_port'], keys: [@global_config['zimbra_key']]) do |ssh|
        puts "[I] -- Extracting users from Zimbra"
        @zimbra_users = ssh.exec!("su - zimbra -c 'zmprov -l gaa'").split("\n")
      end

      to_clean = []

      puts "[I] Depuring Zimbra users to detect missing in AD and white list"
      @zimbra_users.each do |z_user|
        z_user_without_domain = z_user.scan(/([^@]+)/).first

        unless users.include? z_user_without_domain or @global_config['zimbra_white_list'].include? z_user_without_domain.first
          to_clean << z_user
        end
      end

      if to_clean.length > 0
        puts
        puts "[W] Users to delete:"
        to_clean.each do |user|
          puts " -- #{user}"
        end
      end

      if options.delete and to_clean.length > 0
        puts

        unless @yes
          choice = choose("[W] Really do you want delete these accounts?", :yes, :no)
        end

        if @yes or choice == :yes
          puts "[I] Connecting to Zimbra server with SSH to remove users"

          errors = []
          Net::SSH.start(@global_config['zimbra_host'], @global_config['zimbra_user'], password: @global_config['zimbra_pass'], port: @global_config['zimbra_port'], keys: [@global_config['zimbra_key']]) do |ssh|
            progress to_clean do |user|
              print "Remove #{user}"
              out = ssh.exec!("su - zimbra -c 'zmprov deleteAccount #{user}'")

              unless out.exitstatus == 0
                errors << " -- User: #{user} Error: #{out}"
              end
            end
          end

          if errors.length > 0
            puts "[E] Some errors deleting users:"

            errors.each do |error|
              puts error
            end
          end
        end
      end
    else
      puts '[E] Wrong authentication in AD or another error'
    end
  end
end

command :add_from_ad do |c|
end

default_command :remove_from_ad
