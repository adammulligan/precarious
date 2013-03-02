require 'linode'
require 'httparty'

# External IP source (this is a rack app I wrote, feel free to use).
# Should return only the IP as `text/plain`.
IP_SOURCE = 'http://what-is-my-ip.herokuapp.com'

EXTERNAL_IP_ATTEMPT_LIMIT = 10

# Linode API key
API_KEY = ''

# Linode API DomainID
#
# Helpfully, Linode does not document where you can find this, so I
# will.
#
# https://manager.linode.com/dns/domain_zonefile/<your_domain.com>
# The DomainID is the number in square brackets on the first line of the
# zone file, as so:
#
#   ; <your_domain.com> [123456]
DOMAIN_ID = -1

# The most recently retrieved IP address is stored in a text file, and
# used to determine if the current external IP is different from the
# last time the script was executed.
IP_FILE = './ip_cache'

def get_cached_ip
  if File.exists?(IP_FILE)
    ip = File.open(IP_FILE).first
    return ip.gsub("\n", "")  unless ip.nil?
  end

  return ""
end

def set_cached_ip(ip)
  File.open(IP_FILE, 'w') { |f| f.write ip }
end

def get_external_ip
  try_count = 0

  ip = HTTParty.get(IP_SOURCE) rescue Timeout::Error

  until ip.class == HTTParty::Response && ip.code == 200
    if try_count == EXTERNAL_IP_ATTEMPT_LIMIT
      raise "External IP check timed out"
    end

    puts "IP request failed, retrying in 30 seconds..."

    sleep 30
    try_count += 1

    puts "Retrying #{EXTERNAL_IP_ATTEMPT_LIMIT-try_count} more time(s)..."

    ip = HTTParty.get(IP_SOURCE) rescue Timeout::Error
  end

  return ip.to_s
end

puts "### Comparing cached IP with current external IP"

cached_ip = get_cached_ip
external_ip = get_external_ip

puts "Cached IP:"
puts cached_ip
puts "External IP:"
puts external_ip

if cached_ip != external_ip
  l = Linode.new(api_key: API_KEY)

  resources_for_current_ip = l.domain.resource.list(:DomainId => DOMAIN_ID).select { |res| res.target == cached_ip }

  if resources_for_current_ip.length > 0
    puts "### Changing host records with IP #{cached_ip} to #{external_ip}"

    resources_for_current_ip.each do |res|
      print "Updating #{res.name} (#{res.resourceid})..."

      begin
        l.domain.resource.update(:DomainId => DOMAIN_ID, :ResourceId => res.resourceid, :target => external_ip)
        puts "Updated"
      rescue
        puts "Failed"
      end
    end
  else
    puts "No resources with IP #{cached_ip}."
  end

  puts "### Setting IP cache #{external_ip}"
  set_cached_ip(external_ip)
else
  puts 'No change in IP so far, yippee!'
end
