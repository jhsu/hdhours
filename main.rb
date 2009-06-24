#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'dm-core'

$:.unshift(Dir.pwd + '/lib/sinatra/lib')
$:.unshift(Dir.pwd + '/lib/googlecalendar/lib')
require 'sinatra'
require 'googlecalendar'
include Googlecalendar

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
end

def get_sched(initials, guser, gpass, sched="")
  initials = initials.downcase
  unless user = User.first(:initials => initials) 
    user = User.create( :initials => initials, 
                        :created_at => DateTime.now, :updated_at => DateTime.now )
  end

  response = sched.split(/\n/).select { |s| s =~ /^\s+[0-9]{2}|You/i }

  shifts = []
  response.each do |s|
    s = s.split.select { |w| w unless w =~ /qcheck|scheduled/i }

    if s.include?("now") || s.include?("today")
      shift = { :date => DateTime.now, 
                :time => "now - #{s[1]} #{s[2]}",
                :location => s.last.gsub(/!+/, '') } 

    else
      shift = { :date => DateTime.parse(s[0] + " #{(s[2] + s[3]).gsub(/^0/,'')}"),
                :time => "#{(s[2] + s[3]).gsub(/^0/,'')}-#{(s[5] + s[6]).gsub(/^0/,'')}", 
                :location => s.last }
    end

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
  end

  shifts
end

get '/' do
  erb :index
end

post '/' do
  if shifts = get_sched(params[:initials], params[:guser],  params[:gpass], params[:sched])
    erb :index, :locals => { :notice => "Sucessfully added shifts to gCal" }
  else
    erb :index, :locals => { :notice => "Failed" }
  end
end
