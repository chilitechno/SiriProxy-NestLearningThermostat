SiriProxy-NestLearningThermostat
================================
About
-----
Plugin for SiriProxy to communicate with the Nest.com servers to set thermostat temperature or get the status of the thermostat.
This plugin requires a nest.com account and Nest hardware from http://www.nest.com/

This plugin was adapted from SiriProxy-Thermostat plugin to call into nest.com.

Config
------
Copy config-info.yml into ~/.siriproxy/config.yml and edit as appropriate. 

Usage
-----
Say things like:

* 'Set the thermostat to 65 degrees'
* 'Set the nest to 65'
* 'What's the status of the nest'
* 'What is the status of the thermostat'

Examples
-------

* https://twitter.com/#!/the_chilitechno/status/142988344941486080/photo/1
* https://twitter.com/#!/the_chilitechno/status/143031527821938688/photo/1

Caveats
-------
* Currently only works with a single nest thermostat. I don't have multiple thermostats installed so it's hard to test, but should be relatively easy to adapt.
* I tried getting Siri to understand 'Check the status of the Nest' but it kept saying it couldn't look up flight information. This seems to be sporadic because sometimes Siri reads 'Nest' as 'next'

To Do
-----
* Caching of authentication token (currently logs into nest for each request)
* Caching of device information 


