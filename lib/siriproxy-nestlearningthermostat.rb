# encoding: utf-8

require 'rubygems'
require 'httparty'
require 'json'
require 'siri_objects'
require 'pp'
require 'cora'

class SiriProxy::Plugin::NestLearningThermostat < SiriProxy::Plugin
    attr_accessor :nest_email
    attr_accessor :nest_password
    attr_accessor :user_agent
    
    def initialize(config = {})
        self.nest_email = config["email"]
        self.nest_password = config["password"]
        self.user_agent = "Nest/3.0.15 (iOS) os=6.0 platform=iPad3,1"
    end
    
    #capture thermostat status
    listen_for(/(\S+\s)?\S*(?:thermostat|nest).+?status/i) { |name| show_status_of_thermostat(name.strip.downcase) }
    listen_for(/status.+?(\S+\s)?\S*(?:thermostat|nest)/i) { |name| show_status_of_thermostat(name.strip.downcase) }
    
    listen_for(/nest.*away/i) { set_thermostat_away_or_home('away') }
    listen_for(/thermostat.*away/i) { set_thermostat_away_or_home('away') }

    listen_for(/nest.*home/i) { set_thermostat_away_or_home('home')  }
    listen_for(/thermostat.*home/i) { set_thermostat_away_or_home('home')  }
    
    listen_for(/(\S+\s)?\S*(?:thermostat|nest)(s?).*([0-9]{2})/i) { |name,plural,temp| set_thermostat(name.strip.downcase,temp) }

    listen_for(/(\S+\s)?\S*(?:thermostat|nest)(s?).*mode.*(heat|cool|range)/i) { |name,plural,mode| set_thermostat_mode(name.strip.downcase,mode) }
    
    def login_to_nest
        loginRequest = HTTParty.post('https://home.nest.com/user/login',:body => { :username => self.nest_email, :password => self.nest_password }, :headers => { 'User-Agent' => self.user_agent })
                
        authResult = JSON.parse(loginRequest.body) rescue nil
        if authResult
           puts authResult 
        end
        return authResult        
    end
    
    def get_nest_status(access_token, user_id, transport_url)
        transport_host = transport_url.split('/')[2]
        statusRequest = HTTParty.get(transport_url + '/v2/mobile/user.' + user_id, :headers => { 'Host' => transport_host, 'User-Agent' => self.user_agent,'Authorization' => 'Basic ' + access_token, 'X-nl-user-id' => user_id, 'X-nl-protocol-version' => '1', 'Accept-Language' => 'en-us', 'Connection' => 'keep-alive', 'Accept' => '*/*'}) rescue nil
        statusResult = JSON.parse(statusRequest.body) rescue nil
        if statusResult
           puts statusResult 
        end
        return statusResult
    end
    
    # parse time_to_target (thanks to @supaflys)
    def get_time_to_target(statusResult,device_serial_id)
        ttt_string = nil
        thetime = statusResult["shared"][device_serial_id]["$timestamp"]
        time_to_target = statusResult["device"][device_serial_id]["time_to_target"]
        if time_to_target
            if time_to_target > 0
                time_estimate = (time_to_target - (thetime/1000))/60
                time_estimate = time_estimate.round
                ttt_string = "#{time_estimate} minutes"
            end
        end
        return ttt_string
    end
        
    def show_status_of_thermostat(device_name = nil)
        say "Checking the status of the #{device_name} Nest."
        
        Thread.new {            
            authResult = login_to_nest                        
            if authResult   
                access_token = authResult["access_token"]
                user_id = authResult["userid"]
                transport_url = authResult["urls"]["transport_url"]
                
                statusResult = get_nest_status(access_token, user_id, transport_url)
                
                if statusResult
                    structure_id = statusResult["user"][user_id]["structures"][0].split('.')[1]
                    if statusResult["structure"][structure_id]["away"]
                        say "The Nest is currently set to away."
                    else                    
                        devices = statusResult["structure"][structure_id]["devices"]
                        valid_device_name = false
                        devices.each { |device|
                            if device_name == statusResult["shared"][device.split('.')[1]]["name"].downcase
                                valid_device_name = true
                            end
                        }
                        devices.each { |device| 
                            device_serial_id = device.split('.')[1]
                            
                            thermostat_name = statusResult["shared"][device_serial_id]["name"]
                            
                            if valid_device_name == false or ( valid_device_name and thermostat_name.downcase == device_name )
                                current_temp = statusResult["shared"][device_serial_id]["current_temperature"]
                                target_temp = statusResult["shared"][device_serial_id]["target_temperature"]
                                
                                current_humidity = statusResult["device"][device_serial_id]["current_humidity"] 
                                temperature_scale = statusResult["device"][device_serial_id]["temperature_scale"]                        
                                
                                if temperature_scale == "F"
                                    current_temp = (current_temp * 1.8) + 32
                                    current_temp = current_temp.round
                                    target_temp = (target_temp * 1.8) + 32
                                    target_temp = target_temp.round
                                else
                                    current_temp = current_temp.to_f.round(1)
                                    target_temp =  target_temp.to_f.round(1)
                                end
                                                            
                                ttt_string = get_time_to_target(statusResult, device_serial_id)
                                if ttt_string
                                    say "The #{thermostat_name} Nest is currently set to #{target_temp}° and will reach it in " + ttt_string + ". The current temperature is #{current_temp}°" + temperature_scale + " and the relative humidity is #{current_humidity}%."                           
                                else
                                    say "The #{thermostat_name} Nest is currently set to #{target_temp}°. The current temperature is #{current_temp}°" + temperature_scale + " and the relative humidity is #{current_humidity}%."                           
                                end
                            end
                        }
                    end
                else
                    say "Sorry, I couldn't understand the response from Nest.com"
                end
            else
                say "Sorry, I couldn't connect to Nest.com."
            end
            
            request_completed #always complete your request! Otherwise the phone will "spin" at the user!
        }
    end
    
    def set_thermostat_away_or_home(home_away)
        # away / home operate on structure IDs - presumably a structure is a collection of devices
        say "One moment while I set the Nest to " + home_away + "."       
        Thread.new {
            authResult = login_to_nest                        
            if authResult   
                access_token = authResult["access_token"]
                user_id = authResult["userid"]
                transport_url = authResult["urls"]["transport_url"]
                transport_host = transport_url.split('/')[2]
                
                statusResult = get_nest_status(access_token, user_id, transport_url)
                
                if statusResult
                    structure_id = statusResult["user"][user_id]["structures"][0].split('.')[1]    
                    time_since_epoch = Time.now.to_i
                    payload = ''
                    if home_away == 'away'
                        payload = '{"away_timestamp":' + "#{time_since_epoch}" + ',"away":true,"away_setter":0}'
                    else
                        payload = '{"away_timestamp":' + "#{time_since_epoch}" + ',"away":false,"away_setter":0}'
                    end
                    begin
                        awayRequest = HTTParty.post(transport_url + '/v2/put/structure.' + structure_id, :body => payload, :headers => { 'Host' => transport_host, 'User-Agent' => self.user_agent, 'Authorization' => 'Basic ' + access_token, 'X-nl-protocol-version' => '1'})
                        puts awayRequest.body
                    rescue
                        puts 'error: ' 
                    end                    
                    
                    if awayRequest.code == 200
                        say "Ok, I set the Nest to " + home_away + "."                      
                    else
                        say "Sorry, I couldn't set the Nest to " + home_away + "."
                    end                    
                else
                    say "Sorry, I couldn't understand the response from Nest.com"
                end
            end
            request_completed #always complete your request! Otherwise the phone will "spin" at the user!
        }    
    end
    
    def set_thermostat(device_name=nil, temp)
        say "One moment while I set the Nest to #{temp} degrees."        
        Thread.new {
            authResult = login_to_nest             
            
            if authResult   
                access_token = authResult["access_token"]
                user_id = authResult["userid"]
                transport_url = authResult["urls"]["transport_url"]
                transport_host = transport_url.split('/')[2]
                
                statusResult = get_nest_status(access_token, user_id, transport_url)
                
                if statusResult
                    structure_id = statusResult["user"][user_id]["structures"][0].split('.')[1]
					devices = statusResult["structure"][structure_id]["devices"]
					valid_device_name = false
					devices.each { |device|
						if device_name == statusResult["shared"][device.split('.')[1]]["name"].downcase
							valid_device_name = true
						end
					}
					devices.each { |device| 
						device_serial_id = device.split('.')[1]
						thermostat_name = statusResult["shared"][device_serial_id]["name"]
						
						if valid_device_name == false or ( valid_device_name and thermostat_name.downcase == device_name )
							version_id = statusResult["shared"][device_serial_id]["$version"]
							
							
							current_temp = statusResult["shared"][device_serial_id]["current_temperature"]
							target_temp_celsius = temp
							temperature_scale = statusResult["device"][device_serial_id]["temperature_scale"]
							
							if temperature_scale == "F"
								current_temp = (current_temp * 1.8) + 32
								current_temp = current_temp.round
								target_temp_celsius = (temp.to_f - 32.0) / 1.8
								target_temp_celsius = target_temp_celsius.round(5)
							else
								current_temp = current_temp.to_f.round(1)
								target_temp_celsius = target_temp_celsius.to_f
							end
												
							payload = '{"target_change_pending":true,"target_temperature":' + "#{target_temp_celsius}" + '}'
							puts payload
							puts device_serial_id
							puts version_id
							puts 'POST ' + transport_url + '/v2/put/shared.' + device_serial_id
							begin
								tempRequest = HTTParty.post(transport_url + '/v2/put/shared.' + device_serial_id, :body => payload, :headers => { 'Host' => transport_host, 'User-Agent' => self.user_agent, 'Authorization' => 'Basic ' + access_token, 'X-nl-protocol-version' => '1'})
								puts tempRequest.body                        
							rescue
								puts 'error: ' 
							end
												
							if tempRequest.code == 200
								say "Ok, I set the #{thermostat_name} Nest to #{temp}°. The current temperature is #{current_temp}°" + temperature_scale + "."                   
							else
								say "Sorry, I couldn't set the temperature on the Nest."
							end      
						end
					}
                else
                    say "Sorry, I couldn't understand the response from Nest.com"
                end
            else
                say "Sorry, I couldn't connect to Nest.com."
            end
            
            request_completed #always complete your request! Otherwise the phone will "spin" at the user!
        }    
    end

    def set_thermostat_mode(device_name, mode)
        # mode operates on structure IDs - presumably a structure is a collection of devices
        say "One moment while I set the Nest mode to " + mode + "."       
        Thread.new {
            authResult = login_to_nest                        
            if authResult   
                access_token = authResult["access_token"]
                user_id = authResult["userid"]
                transport_url = authResult["urls"]["transport_url"]
                transport_host = transport_url.split('/')[2]
                
                statusResult = get_nest_status(access_token, user_id, transport_url)
                
                if statusResult
                    structure_id = statusResult["user"][user_id]["structures"][0].split('.')[1]
					devices = statusResult["structure"][structure_id]["devices"]
					valid_device_name = false
					devices.each { |device|
						if device_name == statusResult["shared"][device.split('.')[1]]["name"].downcase
							valid_device_name = true
						end
					}
					devices.each { |device| 
						device_id = device.split('.')[1]
						thermostat_name = statusResult["shared"][device_id]["name"]
						
						if valid_device_name == false or ( valid_device_name and thermostat_name.downcase == device_name )
							payload = '{"target_temperature_type":"' + mode.downcase.strip + '"}'
							begin
								moderequest = HTTParty.post(transport_url + '/v2/put/shared.' + device_id, :body => payload, :headers => { 'Host' => transport_host, 'User-Agent' => self.user_agent, 'Authorization' => 'Basic ' + access_token, 'X-nl-protocol-version' => '1'})
								puts moderequest.body
							rescue
								puts 'error: ' 
							end                    

							if moderequest.code == 200
								say "Ok, I set the #{thermostat_name} Nest mode to " + mode + "."                      
							else
								say "Sorry, I couldn't set the #{thermostat_name} Nest mode to " + mode + "."
							end                  
						end
					}
                else
                    say "Sorry, I couldn't understand the response from Nest.com"
                end
            end
            request_completed #always complete your request! Otherwise the phone will "spin" at the user!
        }    
    end
end
