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
    
    def initialize(config = {})
        self.nest_email = config["email"]
        self.nest_password = config["password"]
    end
    
    #capture thermostat status
    listen_for(/thermostat.*status/i) { show_status_of_thermostat }
    listen_for(/status.*thermostat/i) { show_status_of_thermostat }
    listen_for(/nest.*status/i) { show_status_of_thermostat }
    listen_for(/status.*nest/i) { show_status_of_thermostat }
    
    listen_for(/nest.*away/i) { set_thermostat_away_or_home('away') }
    listen_for(/thermostat.*away/i) { set_thermostat_away_or_home('away') }

    listen_for(/nest.*home/i) { set_thermostat_away_or_home('home')  }
    listen_for(/thermostat.*home/i) { set_thermostat_away_or_home('home')  }
    
    listen_for(/thermostat.*([0-9]{2})/i) { |temp| set_thermostat(temp) }
    listen_for(/nest.*([0-9]{2})/i) { |temp| set_thermostat(temp) }
    
    listen_for(/thermostat.*warmer|nest.*warmer/i) { set_thermostat_warmer }
    listen_for(/thermostat.*cooler|nest.*cooler/i) { set_thermostat_cooler }


def login_to_nest
        loginRequest = HTTParty.post('https://home.nest.com/user/login',:body => { :username => self.nest_email, :password => self.nest_password }, :headers => { 'User-Agent' => 'Nest/1.1.0.10 CFNetwork/548.0.4' })
                
        authResult = JSON.parse(loginRequest.body) rescue nil
        if authResult
           puts authResult 
        end
        return authResult        
    end
    
    def get_nest_status(access_token, user_id, transport_url)
        transport_host = transport_url.split('/')[2]
        statusRequest = HTTParty.get(transport_url + '/v2/mobile/user.' + user_id, :headers => { 'Host' => transport_host, 'User-Agent' => 'Nest/1.1.0.10 CFNetwork/548.0.4','Authorization' => 'Basic ' + access_token, 'X-nl-user-id' => user_id, 'X-nl-protocol-version' => '1', 'Accept-Language' => 'en-us', 'Connection' => 'keep-alive', 'Accept' => '*/*'}) rescue nil
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
        
    def show_status_of_thermostat
        say "Checking the status of the Nest."
        
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
                        device_serial_id = statusResult["structure"][structure_id]["devices"][0].split('.')[1]
                        # devices element could contain multiple serial_numbers if multiple thermostats associated to nest account. 
                        # serial number is something like 01AB23CD456789EF
                        
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
                        
                        thermostat_name = statusResult["shared"][device_serial_id]["name"]
                        
                        ttt_string = get_time_to_target(statusResult, device_serial_id)
                        if ttt_string
                            say "The #{thermostat_name} Nest is currently set to #{target_temp}° and will reach it in " + ttt_string + ". The current temperature is #{current_temp}°" + temperature_scale + " and the relative humidity is #{current_humidity}%."                           
                        else
                            say "The #{thermostat_name} Nest is currently set to #{target_temp}°. The current temperature is #{current_temp}°" + temperature_scale + " and the relative humidity is #{current_humidity}%."                           
                        end
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
                        awayRequest = HTTParty.post(transport_url + '/v2/put/structure.' + structure_id, :body => payload, :headers => { 'Host' => transport_host, 'User-Agent' => 'Nest/1.1.0.10 C.10 CFNetwork/548.0.4', 'Authorization' => 'Basic ' + access_token, 'X-nl-protocol-version' => '1'})
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
    
    def set_thermostat(temp)
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
                    device_serial_id = statusResult["structure"][structure_id]["devices"][0].split('.')[1]
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
                                        
                    thermostat_name = statusResult["shared"][device_serial_id]["name"]
                                        
                    payload = '{"target_change_pending":true,"target_temperature":' + "#{target_temp_celsius}" + '}'
                    puts payload
                    puts device_serial_id
                    puts version_id
                    puts 'POST ' + transport_url + '/v2/put/shared.' + device_serial_id
                    begin
                        tempRequest = HTTParty.post(transport_url + '/v2/put/shared.' + device_serial_id, :body => payload, :headers => { 'Host' => transport_host, 'User-Agent' => 'Nest/1.1.0.10 C.10 CFNetwork/548.0.4', 'Authorization' => 'Basic ' + access_token, 'X-nl-protocol-version' => '1'})
                        puts tempRequest.body                        
                    rescue
                        puts 'error: ' 
                    end
                                        
                    if tempRequest.code == 200
                        say "Ok, I set the #{thermostat_name} Nest to #{temp}°. The current temperature is #{current_temp}°" + temperature_scale + "."                   
                    else
                        say "Sorry, I couldn't set the temperature on the Nest."
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
    
    def set_thermostat_cooler
        say "One moment while I lower the Nest temperature."        
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
                    device_serial_id = statusResult["structure"][structure_id]["devices"][0].split('.')[1]
                    version_id = statusResult["shared"][device_serial_id]["$version"]
                    
                    
                    current_temp = statusResult["shared"][device_serial_id]["current_temperature"]
                    #target_temp_celsius = temp
                    temperature_scale = statusResult["device"][device_serial_id]["temperature_scale"]
                    
                    if temperature_scale == "F"
                        current_temp = (current_temp * 1.8) + 32
                        current_temp = current_temp.round
                        target_temp_celsius = (current_temp - 1 - 32.0) / 1.8
                        target_temp_celsius = target_temp_celsius.round(5)
                    else
                        current_temp = current_temp.to_f.round(1)
                        target_temp_celsius = current_temp - 1
                    end
                                        
                    thermostat_name = statusResult["shared"][device_serial_id]["name"]
                                        
                    payload = '{"target_change_pending":true,"target_temperature":' + "#{target_temp_celsius}" + '}'
                    puts payload
                    puts device_serial_id
                    puts version_id
                    puts 'POST ' + transport_url + '/v2/put/shared.' + device_serial_id
                    begin
                        tempRequest = HTTParty.post(transport_url + '/v2/put/shared.' + device_serial_id, :body => payload, :headers => { 'Host' => transport_host, 'User-Agent' => 'Nest/1.1.0.10 C.10 CFNetwork/548.0.4', 'Authorization' => 'Basic ' + access_token, 'X-nl-protocol-version' => '1'})
                        puts tempRequest.body                        
                    rescue
                        puts 'error: ' 
                    end
                                        
                    if tempRequest.code == 200
                        say "Ok, I set the #{thermostat_name} Nest to #{temp}°. The current temperature is #{current_temp}°" + temperature_scale + "."                   
                    else
                        say "Sorry, I couldn't set the temperature on the Nest."
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

    def set_thermostat_warmer
        say "One moment while I lower the Nest temperature."        
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
                    device_serial_id = statusResult["structure"][structure_id]["devices"][0].split('.')[1]
                    version_id = statusResult["shared"][device_serial_id]["$version"]
                    
                    
                    current_temp = statusResult["shared"][device_serial_id]["current_temperature"]
                    #target_temp_celsius = temp
                    temperature_scale = statusResult["device"][device_serial_id]["temperature_scale"]
                    
                    if temperature_scale == "F"
                        current_temp = (current_temp * 1.8) + 32
                        current_temp = current_temp.round
                        target_temp_celsius = (current_temp + 1 - 32.0) / 1.8
                        target_temp_celsius = target_temp_celsius.round(5)
                    else
                        current_temp = current_temp.to_f.round(1)
                        target_temp_celsius = current_temp + 1
                    end
                                        
                    thermostat_name = statusResult["shared"][device_serial_id]["name"]
                                        
                    payload = '{"target_change_pending":true,"target_temperature":' + "#{target_temp_celsius}" + '}'
                    puts payload
                    puts device_serial_id
                    puts version_id
                    puts 'POST ' + transport_url + '/v2/put/shared.' + device_serial_id
                    begin
                        tempRequest = HTTParty.post(transport_url + '/v2/put/shared.' + device_serial_id, :body => payload, :headers => { 'Host' => transport_host, 'User-Agent' => 'Nest/1.1.0.10 C.10 CFNetwork/548.0.4', 'Authorization' => 'Basic ' + access_token, 'X-nl-protocol-version' => '1'})
                        puts tempRequest.body                        
                    rescue
                        puts 'error: ' 
                    end
                                        
                    if tempRequest.code == 200
                        say "Ok, I set the #{thermostat_name} Nest to #{temp}°. The current temperature is #{current_temp}°" + temperature_scale + "."                   
                    else
                        say "Sorry, I couldn't set the temperature on the Nest."
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

end
