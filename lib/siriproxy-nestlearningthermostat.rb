require 'rubygems'
require 'httparty'
require 'json'
#require 'addressable/uri'

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
    
    listen_for(/thermostat.*([0-9]{2})/i) { |temp| set_thermostat(temp) }
    
    listen_for(/temperature.*inside/i) { show_temperature }
    listen_for(/inside.*temperature/i) { show_temperature }
    listen_for(/temperature.*in here/i) { show_temperature }
    
    def show_status_of_thermostat
        say "Checking the status of the Nest."
        
        Thread.new {
            # first request to login to nest
            loginRequest = HTTParty.post('https://home.nest.com/user/login',:body => { :username => self.nest_email, :password => self.nest_password }, :headers => { 'User-Agent' => 'Nest/1.1.0.10 CFNetwork/548.0.4' })
            
            authResult = JSON.parse(loginRequest.body) rescue nil
            
            if authResult   
                access_token = authResult["access_token"]
                user_id = authResult["userid"]
                transport_url = authResult["urls"]["transport_url"]
                transport_host = transport_url.split('/')[2]
                
                # use access token to get response from nest in another request
                statusRequest = HTTParty.get(transport_url + '/v2/mobile/user.' + user_id, :headers => { 'Host' => transport_host, 'User-Agent' => 'Nest/1.1.0.10 CFNetwork/548.0.4','Authorization' => 'Basic ' + access_token, 'X-nl-user-id' => user_id, 'X-nl-protocol-version' => '1', 'Accept-Language' => 'en-us', 'Connection' => 'keep-alive', 'Accept' => '*/*'}) rescue nil
                # puts statusRequest.code
                # puts statusRequest.body
                statusResult = JSON.parse(statusRequest.body) rescue nil
                
                if statusResult
                    structure_id = statusResult["user"][user_id]["structures"][0].split('.')[1]
                    device_id = statusResult["structure"][structure_id]["devices"][0].split('.')[1]
                    current_temp = (statusResult["shared"][device_id]["current_temperature"] * 1.8) + 32
                    current_temp = current_temp.round
                    target_temp = (statusResult["shared"][device_id]["target_temperature"] * 1.8) + 32
                    target_temp = target_temp.round
                    thermostat_name = statusResult["shared"][device_id]["name"]
                    say "The #{thermostat_name} Nest is currently set to #{target_temp} degrees. The current temperature is #{current_temp} degrees."
                else
                    say "Sorry, I couldn't understand the response from Nest.com"
                end
            else
                say "Sorry, I couldn't connect to Nest.com."
            end
            
            request_completed #always complete your request! Otherwise the phone will "spin" at the user!
        }
    end
    
    def set_thermostat(temp)
        say "One moment while I set the Nest to #{temp} degrees."        
        Thread.new {
            begin
                loginRequest = HTTParty.post('https://home.nest.com/user/login',:body => { :username => self.nest_email, :password => self.nest_password }, :headers => { 'User-Agent' => 'Nest/1.1.0.10 CFNetwork/548.0.4' })
            rescue
                puts 'login error'
            end
            
            authResult = JSON.parse(loginRequest.body) rescue nil
            
            if authResult   
                access_token = authResult["access_token"]
                user_id = authResult["userid"]
                transport_url = authResult["urls"]["transport_url"]
                transport_host = transport_url.split('/')[2]
                puts transport_url
                puts transport_host
                puts user_id
                puts access_token
                
                # use access token to get response from nest in another request
                statusRequest = HTTParty.get(transport_url + '/v2/mobile/user.' + user_id, :headers => { 'Host' => transport_host, 'User-Agent' => 'Nest/1.1.0.10 CFNetwork/548.0.4','Authorization' => 'Basic ' + access_token, 'X-nl-user-id' => user_id, 'X-nl-protocol-version' => '1', 'Accept-Language' => 'en-us', 'Connection' => 'keep-alive', 'Accept' => '*/*'}) rescue nil
                puts statusRequest.code
                puts statusRequest.body
                statusResult = JSON.parse(statusRequest.body) rescue nil
                
                if statusResult
                    structure_id = statusResult["user"][user_id]["structures"][0].split('.')[1]
                    device_id = statusResult["structure"][structure_id]["devices"][0].split('.')[1]
                    version_id = statusResult["shared"][device_id]["$version"]
                    current_temp = (statusResult["shared"][device_id]["current_temperature"] * 1.8) + 32
                    current_temp = current_temp.round
                    thermostat_name = statusResult["shared"][device_id]["name"]
                    
                    target_temp_celsius = (temp.to_f - 32.0) / 1.8
                    target_temp_celsius = target_temp_celsius.round(5)
                    
                    payload = '{"target_change_pending":true,"target_temperature":' + "#{target_temp_celsius}" + '}'
                    puts payload
                    puts device_id
                    puts version_id
                    puts 'POST ' + transport_url + '/v2/put/shared.' + device_id
                    begin
                        tempRequest = HTTParty.post(transport_url + '/v2/put/shared.' + device_id, :body => payload, :headers => { 'Host' => transport_host, 'User-Agent' => 'Nest/1.1.0.10 C.10 CFNetwork/548.0.4', 'Authorization' => 'Basic ' + access_token, 'X-nl-protocol-version' => '1'})
                    rescue
                        puts 'error: ' 
                    end
                    
                    puts "continuing"
                    puts tempRequest.code
                    puts tempRequest.body
                    
                    if tempRequest.code == 200
                        say "Ok, I set the #{thermostat_name} Nest to #{temp} degrees. The current temperature is #{current_temp} degrees."                        
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
    
    def show_temperature
        say "Checking the inside temperature."
        
        Thread.new {
            
            request_completed #always complete your request! Otherwise the phone will "spin" at the user!
        }
    end
end
