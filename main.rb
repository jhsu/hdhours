#!/usr/bin/env ruby
require 'sinatra'
require 'net/http'
require 'uri'
require 'dm-core'
require 'googlecalendar'
include Googlecalendar
require 'yaml'

CONFIG = YAML.load_file("#{Dir.pwd}/config.yml")
GUSER = CONFIG['USER']
GPASS = CONFIG['PASS']


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

def get_sched(initials)
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
  
  user.update_attributes(:last_shift => shifts.last[:date]) unless shifts.empty?

  g = GData.new
  g.login(GUSER, GPASS, source="labs.josephhsu.com")
  shifts.each do |shift| 
    g.quick_add("#{shift[:date].strftime('%b %d, %Y')} #{shift[:time]} Helpdesk #{shift[:location]}")
  end
end

get '/' do
end
