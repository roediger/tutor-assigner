require 'rubygems'
require 'sinatra'
require 'sinatra/assetpack'
require 'erb'
require 'coffee_script'
require 'json'
require 'digest/sha2'
require 'pstore'
require 'time'
require 'data_mapper'
require 'pony'

require './config.rb'


class App < Sinatra::Base
  set :port, 9999
  set :root, File.dirname(__FILE__)
  register Sinatra::AssetPack
  
  DataMapper.setup(:default,"sqlite://#{Dir.pwd}/assigner.db")


  class Registration
    include DataMapper::Resource
    property :reghash, String, :length=>100, :key => true
    property :title, String, :length=>100
    property :name, String, :length=>100
    property :email, String, :length=>200
    property :groups, Text
    property :created_at, DateTime
    property :updated_at, DateTime
    has n,:tutors
  end
  
  class Tutor
    include DataMapper::Resource
    property :tutorhash, String, :length=>100, :key => true
    property :name, String, :length=>100
    property :email, String, :length=>200
    property :available, Text
    property :created_at, DateTime
    property :updated_at, DateTime    
    belongs_to :registration
  end

  DataMapper.finalize
  DataMapper.auto_upgrade!
  
  assets {
      serve '/js',     from: 'js'
      serve '/css',    from: 'css'
      serve '/images', from: 'images'

      js  :app, [ '/js/vendor/jquery*','/js/vendor/handle*','/js/vendor/*' ]
      css :app, [ '/css/bootstrap.css','/css/bootstrap-fix.css','/css/bootstrap-responsive.css','/css/*','/css/**/*' ]
      js  :register, [ '/js/register.js' ]
      js  :vote, [ '/js/vote.js' ]
      js  :manage, [ '/js/manage.js' ]
  }
  
  helpers do
    def hashThis(data)
      (Digest::SHA2.new << data).to_s
    end
  end  
  
  get '/vote/:hash' do
    tutor=Tutor.first(:tutorhash => params[:hash])
    @name=tutor.name
    @groups=tutor.registration.groups;
    @avail=tutor.available;
    @hash=params[:hash]
    erb :vote
  end
  
  post '/vote/:hash' do
    tutor=Tutor.first(:tutorhash => params[:hash])
    tutor.available=JSON.generate(params[:available]);
    tutor.save    
  end
  
  get '/manage/:hash' do
    reg=Registration.first(:reghash => params[:hash])
    @tutors=JSON.generate(reg.tutors.all)
    erb :manage
  end
  
  post '/manage/:hash/email' do
    reg=Registration.first(:reghash => params[:hash])
    raise unless reg
    
    @title=reg.title
    
    reg.tutors.each do |tutor|      
      @url=CONFIG[:baseurl]+"/vote/"+tutor.tutorhash
      Pony.mail PONY_OPTS.merge({ 
        :to => "muehe@in.tum.de",
        :subject => "Tutorial Assignment for #{reg.title} #{tutor.email}",
        :body => erb(:email_vote)
      })
      break;
    end
  end

  get '/' do
    redirect '/register'
  end

  get '/register' do
    erb :register
  end

  post '/register' do
    hash=hashThis(params.flatten(10).join(","))
    reg=Registration.first_or_create(:reghash=>hash)
    reg.name=params['name']
    reg.title=params['title']
    reg.email=params['email']
    reg.groups=JSON.generate(params['groups'])
    
    params['tutors'].each do |tutor|
      tutorHash=hashThis(hash+tutor[1]['email'])
      tutorData=tutor[1]
      tutor=Tutor.first_or_create(:tutorhash=>tutorHash)
      tutor.name=tutorData['name']
      tutor.email=tutorData['email']
      tutor.save
      reg.tutors << tutor
    end
    reg.save
    
    @title=reg.title
    @url=CONFIG[:baseurl]+"/manage/"+hash
    Pony.mail CONFIG[:pony_opts].merge({
      :to => reg.email,
      :subject => "Tutorial Assignment for #{reg.title}",
      :body => erb(:email_register)
    })
                
    hash
  end
  
  run! if app_file == $0
end

