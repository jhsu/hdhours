#!/usr/bin/env ruby
require 'sinatra'
require 'net/http'
require 'uri'
require 'dm-core'
require 'googlecalendar'
include Googlecalendar
require 'yaml'

configure do
  CONFIG = YAML.load_file("#{Dir.pwd}/config.yml")
  GUSER = CONFIG['USER']
  GPASS = CONFIG['PASS']
end

DataMapper::setup(:default, "sqlite3://#{Dir.pwd}/helpdesk.sql")

class User
  include DataMapper::Resource
  property :id, Serial
  property :initials, Text
  property :last_shift, DateTime
  property :created_at, DateTime
  property :updated_at, DateTime

  def slast_shift
    if self.last_shift
      self.last_shift.strftime('%b %d, %Y')
    else
      nil
    end
  end

  def get_sched
    `ssh jshsu@ubunix.buffalo.edu 'qc -a #{self.initials} | grep @'`
  end
end

def get_sched(initials, guser, gpass)
  initials = initials.downcase
  unless user = User.first(:initials => initials) 
    user = User.create( :initials => initials, 
                        :created_at => DateTime.now, :updated_at => DateTime.now )
  end

  response = user.get_sched.split(/\n/).select {|s| s =~ /[0-9]/}

  shifts = []
  response.each do |s|
    s = s.split
    shift = { :date => DateTime.parse(s[0] + " " + (s[2] + s[3]).gsub(/^0/,'')), 
              :time => "#{(s[2] + s[3]).gsub(/^0/,'')}-#{(s[5] + s[6]).gsub(/^0/,'')}", 
              :location => s.last }

    if user.last_shift
      shifts << shift unless user.last_shift >= shift[:date]
    else
      shifts << shift
    end
  end
  
  if (guser && gpass)
    user.update_attributes(:last_shift => shifts.last[:date]) unless shifts.empty?

    g = GData.new
    g.login(guser, gpass, source="labs.josephhsu.com")
    shifts.each do |shift| 
      g.quick_add("#{shift[:date].strftime('%b %d, %Y')} #{shift[:time]} Helpdesk::#{initials} #{shift[:location]}")
    end
  else
    false
  end
end

get '/' do
  erb :index
end

post '/gcal' do
  if get_sched(params[:initials], params[:guser], params[:gpass])
    redirect '/'
  else
    erb "Failed"
  end
end

post '/last_shift/clear' do
  User.first(:initials => params[:initials]).update_attributes(:last_shift => nil)
  redirect '/'
end
