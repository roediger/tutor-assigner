require 'rubygems'
require 'sinatra/base'
require 'sinatra/assetpack'
require 'erb'
require 'coffee_script'
require 'json'
require 'digest/sha2'
require 'pstore'
require 'time'
require 'data_mapper'
require 'pony'
require 'date'

require './config.rb'


class App < Sinatra::Base
  set :logging, :true
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
    has n,:groups
  end
  
  # class Group
  #   include DataMapper::Resource
  #   property :id, Serial
  #   property :name, String, :length=>100
  #   property :when, DateTime
  #   property :created_at, DateTime
  #   property :updated_at, DateTime    
  #   belongs_to :registration
  #   belongs_to :tutor
  # end
  
  class Tutor
    include DataMapper::Resource
    property :tutorhash, String, :length=>100, :key => true
    property :name, String, :length=>100
    property :email, String, :length=>200
    property :available, Text
    property :created_at, DateTime
    property :updated_at, DateTime    
    belongs_to :registration
    has n,:groups
  end

  DataMapper.finalize
  DataMapper.auto_upgrade!
  
  assets {
      serve '/js',     from: 'js'
      serve '/css',    from: 'css'
      serve '/images', from: 'images'

      js  :app, [ '/js/vendor/jquery-1.8.2.min.js','/js/vendor/jquery-ui-1.8.23.custom.min.js','/js/vendor/handlebars-1.0.rc.1.js','/js/vendor/bootstrap.min.js' ]
      css :app, [ '/css/bootstrap.css','/css/bootstrap-fix.css','/css/bootstrap-responsive.css','/css/*','/css/**/*' ]
      js  :register, [ '/js/vendor/jquery.validate.js','/js/register.js' ]
      js  :vote, [ '/js/vendor/fullcalendar.min.js','/js/vote.js' ]
      js  :manage, [ '/js/vendor/fullcalendar.min.js','/js/manage.js' ]
  }
  
  helpers do
    def hashThis(data)
      (Digest::SHA2.new << data).to_s
    end
  end  
  
  get '/vote/:hash' do
    tutor=Tutor.first(:tutorhash => params[:hash])
    @name=tutor.name
    @groups=tutor.registration.groups
    @avail=tutor.available
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
    @groups=reg.groups
    erb :manage
  end
  
  post '/manage/:hash/solve' do
    reg=Registration.first(:reghash => params[:hash])
    raise unless reg
    
    tutors = reg.tutors
    groups = JSON.parse(reg.groups).values.map { |g| g.merge('slot' => "#{g['day']} #{g['time']}") }
    slots={} ; groups.each_index { |i| (slots[groups[i]['slot']]||=[]) << i }
    
    cplex = "Maximize\n"
    cplex+= " obj: "
    
    vars=[]
    tutors.length.times do |t|
      groups.length.times do |g|
        if tutors[t].available then
          weight=JSON.parse(tutors[t].available)[groups[g]['slot']]=="true" ? " + " : " - "
          vars << "#{weight} t#{t}g#{g}"
        else
          vars << "- t#{t}g#{g}"
        end
      end
    end    
    cplex+=vars.join("")+"\n"
    
    cplex+= "Subject To\n"
    
    # At most one tutor for each group
    groups.length.times do |g|
      vars=[]
      tutors.length.times do |t|
        vars << "t#{t}g#{g}"
      end
      cplex += " g#{g}: " + vars.join(" + ")+" <= 1\n"
    end  
    
    # At most 2 groups per tutor
    tutors.length.times do |t|
      vars=[]
        groups.length.times do |g|
        vars << "t#{t}g#{g}"
      end
      cplex += " t#{t}: " + vars.join(" + ")+" <= 2\n"
    end
    
    # At most 1 group per tutor in the same time slot
    slotIndex=0
    slots.each do |slot,groupIndexes|
      tutors.length.times do |t|
        vars=[]
        groupIndexes.each do |g|
          vars << "t#{t}g#{g}"
        end
        cplex += " s#{slotIndex}t#{t}: " + vars.join(" + ") + " <= 1\n"
      end
      slotIndex+=1
    end
    
    vars=[]
    tutors.length.times do |t|
      groups.length.times do |g|
        vars << "t#{t}g#{g}"
      end
    end    
    cplex+="Binary\n"
    cplex+=" "+vars.join(" ")+"\n"
        
    IO.write("solve.cplex",cplex)
    system("glpsol --lp solve.cplex -o sol")
    
    c=IO.read("sol")
    
    result=Hash.new
    c.split(/\n/).each do |line|
      cols=line.split(/[\s\t]+/)
      if cols[3]=="*" and cols[4]=="1"
        p line
        m=cols[2].match(/t(\d+)g(\d+)/)
        t=m[1].to_i
        g=m[2].to_i
        result[groups[g]['name']]=tutors[t].name
      end
    end
    p result
    p result.length
    content_type :json
    JSON.generate(result)
  end
  
  post '/manage/:hash/email' do
    reg=Registration.first(:reghash => params[:hash])
    raise unless reg
    
    @title=reg.title
    
    reg.tutors.each do |tutor|      
      @url=CONFIG[:baseurl]+"/vote/"+tutor.tutorhash
      Pony.mail CONFIG[:pony_opts].merge({ 
        :to => tutor.email,
        :subject => "Tutorial Assignment for #{reg.title}",
        :body => erb(:email_vote)
      })
      puts "Emailed #{tutor.email}..."
    end
    ""
  end

  get '/' do
    expires 3600*24, :public, :must_revalidate
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
  
  run!
end

