require 'nokogiri'
require 'capybara/poltergeist'
require 'lastfm'
require 'json'

SCROBBLE_THRESHOLD_DAYS = 1
$scrobbled = []
SCROBBLES_FILE="scrobbles.json"
SESSION_FILE="session.txt"

def load_scrobbled
  begin
    file = IO.read(SCROBBLES_FILE)
    $scrobbled = JSON.load(file)
  rescue
    puts "error reading file"
    $scrobbled = []
  end
  puts "loaded scrobbles: #{$scrobbled}"
end

def write_scrobbled
  unless $scrobbled.empty?
    unless File.exists?(SCROBBLES_FILE) #unnecessary
      file = File.new(SCROBBLES_FILE, 'w')
    else
      file = File.open(SCROBBLES_FILE, 'w')
    end
    file.puts JSON.dump($scrobbled)
    file.close
    puts "wrote scrobbles to file"
  end
end

def save_session(session)
  puts "saving session: #{session}"
  file = File.new(SESSION_FILE, 'w')
  file.puts session
  file.close
  puts "wrote session to file"
end
 

def load_session
  if File.exists?(SESSION_FILE)
    begin
      return IO.read(SESSION_FILE)
    rescue
      puts "error reading session"
    end
  else
    puts "no session file"
  end
end

def scrobbled? song
  $scrobbled.each do |scr|
    if scr["timestamp"] == song[:timestamp] and scr["title"] == song[:title]
      puts "already scrobbled!"
      return true
    end
  end
  false

end

def scrape
  @songs = []
  
  session = Capybara::Session.new(:poltergeist)
  session.visit "http://www.facebook.com"
  sleep 2

  begin
    session.find("#email").set(ENV['FACEBOOK_LOGIN'])
    session.find("#pass").set(ENV['FACEBOOK_PASS'])
    session.find("input[value='Log In']").click
  rescue 
    session.visit "http://www.facebook.com"
    sleep 3
    session.find("#email").set(ENV['FACEBOOK_LOGIN'])
    session.find("#pass").set(ENV['FACEBOOK_PASS'])
    session.find("input[value='Log In']").click
  end
  session.visit "http://www.shazam.com/myshazam"
  sleep 2
  parsed = Nokogiri::HTML(session.html)
  parsed.css("article.tl-container").each do |article|
    title = article.at_css(".tl-title a").content.strip
    artist = article.at_css(".tl-artist").content.strip
    timestamp = article.at_css(".tl-date")["data-time"]
    song = { 
      title: title, 
      artist: artist,
      timestamp: timestamp,
      datetime:  DateTime.strptime(timestamp, "%Q")
    }
    @songs.push(song)
  end
  scrobble(@songs)
end

def scrobble(songs)
  if songs.length
    load_scrobbled
    
    now = DateTime.now()
    @session = load_session
    lastfm = Lastfm.new(ENV['LASTFM_KEY'], ENV['LASTFM_SECRET'])
    if @session.nil? or @session.empty?
      token = lastfm.auth.get_token
      puts "Time to authorize! Please visit: http://www.last.fm/api/auth/?api_key=#{ENV['LASTFM_KEY']}&token=#{token} then press return"
      gets.chomp
      lastfm.session = lastfm.auth.get_session(token: token)['key']
      save_session(lastfm.session)
    else
      lastfm.session = @session
    end

    songs.each do |song|
      if now - song[:datetime] < SCROBBLE_THRESHOLD_DAYS
        unless scrobbled? song
          puts "ok to scrobble #{song[:title]}"
          lastfm.track.scrobble(artist: song[:artist], track: song[:title])
          $scrobbled.push(song)
        end
      end
    end
  end
  write_scrobbled
end
scrape

