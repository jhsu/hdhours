#!/usr/bin/env ruby
require 'rubygems'
require 'net/http'
require 'uri'
require 'dm-core'

$:.unshift(Dir.pwd + '/lib/sinatra/lib')
$:.unshift(Dir.pwd + '/lib/googlecalendar/lib')
require 'sinatra'
require 'googlecalendar'
include Googlecalendar

DataMapper::setup(:default, ENV['DATABASE_URL'] || "sqlite3://helpdesk.db")

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
    g = GData.new
    if g.login(guser, gpass, source="labs.josephhsu.com")
      user.update_attributes(:last_shift => shifts.last[:date]) unless shifts.empty?
      shifts.each do |shift| 
        g.quick_add("#{shift[:date].strftime('%b %d, %Y')} #{shift[:time]} Helpdesk::#{initials} #{shift[:location]}")
      end
    end
  end

  shifts
end

get '/' do
  erb :index
end

post '/' do
  initials = params[:initials]
  guser = params[:guser]
  gpass = params[:gpass]
  qc = params[:sched]
  if (initials == "" || guser == "" || gpass == "" || qc == "")
    erb :index, :locals => { :notice => "Please fill out all fields" }
  else
    if shifts = get_sched(initials, guser, gpass, qc)
      erb :index, :locals => { :notice => "Sucessfully added shifts to gCal" }
    else
      erb :index, :locals => { :notice => "Failed. Please check all fields." }
    end
  end
end
