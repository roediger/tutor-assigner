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
require 'open3'

require './config.rb'


class App < Sinatra::Base
  set :logging, :true
  set :port, 9999
  set :root, File.dirname(__FILE__)
  register Sinatra::AssetPack
  
  DataMapper::Model.raise_on_save_failure = true
  #DataMapper::Logger.new(STDOUT, :debug)
  DataMapper.setup(:default,"sqlite://#{Dir.pwd}/assigner.db")

  class Registration
    include DataMapper::Resource
    property :id, Serial
    property :access_code, String, :length=>200, :index=>true, :default => lambda { |r,p| (Digest::SHA2.new << Random.new.bytes(60)).to_s }
    property :title, String, :length=>100
    property :name, String, :length=>100
    property :email, String, :length=>200
    property :created_at, DateTime
    property :updated_at, DateTime
    has n,:tutors
    has n,:groups
  end
  
  class Group
    include DataMapper::Resource
    property :id, Serial
    property :name, String, :length=>100
    property :when, DateTime
    property :created_at, DateTime
    property :updated_at, DateTime    
    belongs_to :registration
    belongs_to :tutor, :required=>false
    has n,:preferences
  end
  
  class Tutor
    include DataMapper::Resource
    property :id, Serial
    property :access_code, String, :length=>200, :index=>true, :default => lambda { |r,p| (Digest::SHA2.new << Random.new.bytes(60)).to_s }
    property :name, String, :length=>100
    property :email, String, :length=>200
    property :created_at, DateTime
    property :updated_at, DateTime    
    belongs_to :registration
    has n,:groups
    has n,:preferences
  end
  
  class Preference
    include DataMapper::Resource
    property :id, Serial
    property :weight, Integer
    belongs_to :group
    belongs_to :tutor    
  end

  DataMapper.finalize
  DataMapper.auto_upgrade!
  
  assets {
      serve '/js',     from: 'js'
      serve '/css',    from: 'css'
      serve '/images', from: 'images'

      js  :app, [ '/js/vendor/jquery-1.8.2.min.js','/js/vendor/jquery-ui-1.8.23.custom.min.js','/js/vendor/handlebars-1.0.rc.1.js','/js/vendor/bootstrap.min.js','/js/vendor/date.js' ]
      css :app, [ '/css/bootstrap.css','/css/bootstrap-fix.css','/css/bootstrap-responsive.css','/css/*','/css/**/*' ]
      js  :register, [ '/js/vendor/jquery.validate.js','/js/register.js' ]
      js  :vote, [ '/js/vendor/fullcalendar.min.js','/js/vote.js' ]
      js  :manage, [ '/js/vendor/fullcalendar.min.js','/js/manage.js' ]
  }
  
  helpers do
    def accessCode
      ash(id)
      Base64.encode64(id.to_s + "--" + Random.new.bytes(99))
    end
    
    def dayToInt(day)
      return 1 if day=="Mo"
      return 2 if day=="Di"
      return 3 if day=="Mi"
      return 4 if day=="Do"
      return 5 if day=="Fr"
    end
  end  
  
  get '/vote/:id/:access_code' do
    tutor=Tutor.first(:id => params[:id],:access_code => params[:access_code])
    raise unless tutor
    
    slots={} ; tutor.registration.groups.each { |g| (slots[g.when]||=[]) << g.id }
    prefs={} ; tutor.preferences.each { |pref| prefs[pref.group.id]=pref.weight }
    @tutor=JSON.generate(tutor)
    @slots=JSON.generate(slots)
    @prefs=JSON.generate(prefs)
    erb :vote
  end
  
  post '/vote/:id/:access_code' do
    tutor=Tutor.first(:id => params[:id],:access_code => params[:access_code])
    raise unless tutor

    params['prefs'].each do |g,weight|
      pref=tutor.preferences.first_or_new({:group => Group.first(:id => g.to_i)})
      pref.weight=weight.to_i > 0 ? 1 : 0
      pref.save
    end    
    tutor.save
    
    true
  end
  
  get '/manage/:id/:access_code' do
    reg=Registration.first(:id => params[:id],:access_code => params[:access_code])
    raise unless reg
        
    @tutors=JSON.generate(reg.tutors.all.map { |t| 
      t.attributes.merge({:gcount => t.preferences.all(:weight => 1).length}) 
    })
    @groups=JSON.generate(reg.groups)
    erb :manage
  end
  
  post '/manage/:id/:access_code/solve' do
    reg=Registration.first(:id => params[:id],:access_code => params[:access_code])
    raise unless reg
    
    groups=reg.groups
    tutors=reg.tutors
    
    cplex = "Maximize\n"
    cplex+= " obj: "
    
    # Build objective function: add all variables while considering their weight
    tutors.each do |tutor|
      groups.each do |group|
        pref=tutor.preferences.first(:group => group)
        weight=pref ? pref.weight : 0
        
        cplex+= " + #{weight} t#{tutor.id}g#{group.id}"
      end
    end
    
    cplex+= "\n"
    cplex+= "Subject To\n"

    # At most one tutor for each group
    groups.each do |group|
      vars=[]
      tutors.each do |tutor|
        vars << "t#{tutor.id}g#{group.id}"
      end
      cplex += " g#{group.id}: " + vars.join(" + ")+" <= 1\n"      
    end
    
    # At most 2 groups per tutor
    tutors.each do |tutor|
      vars=[]
      groups.each do |group|
        vars << "t#{tutor.id}g#{group.id}"
      end
      cplex += " t#{tutor.id}: " + vars.join(" + ")+" <= 2\n"
    end
    
    # At most 1 group per tutor in the same time slot
    slots={} ; groups.each { |group| (slots[group.when]||=[]) << group.id }
    slotIndex=0
    slots.each do |slot,groupIndexes|
      tutors.each do |tutor|
        vars=[]
        groupIndexes.each do |g|
          vars << "t#{tutor.id}g#{g}"
        end
        cplex += " s#{slotIndex}t#{tutor.id}: " + vars.join(" + ") + " <= 1\n"
      end
      slotIndex+=1
    end
    
    vars=[]
    tutors.each do |tutor|
      groups.each do |group|
        vars << "t#{tutor.id}g#{group.id}"
      end
    end    
    cplex+="Binary\n"
    cplex+=" "+vars.join(" ")+"\n"
    
    out,solution,status=Open3.capture3("glpsol --lp /dev/stdin -o /dev/stderr",:stdin_data=>cplex)

    result=Hash.new
    solution.split(/\n/).each do |line|
      cols=line.split(/[\s\t]+/)
      if cols[3]=="*" and cols[4]=="1"
        m=cols[2].match(/t(\d+)g(\d+)/)
        t=m[1].to_i
        g=m[2].to_i
        result[Group.first(:id => g).name]=Tutor.first(:id => t).name
      end
    end
    
    content_type :json
    JSON.generate(result)
  end
  
  post '/manage/:id/:access_code/email' do
    reg=Registration.first(:id => params[:id],:access_code => params[:access_code])
    raise unless reg
    
    @title=reg.title
    reg.tutors.each do |tutor|      
      @url=CONFIG[:baseurl]+"/vote/#{tutor.id}/#{tutor.access_code}"
      Pony.mail CONFIG[:pony_opts].merge({ 
        :to => tutor.email,
        :subject => "Tutorial Assignment for #{reg.title}",
        :body => erb(:email_vote)
      })
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
    reg=Registration.create({
      :name=>params['name'],
      :title=>params['title'],
      :email=>params['email']
    })    
    params['groups'].each do |key,group|
      whenDate=DateTime.new(2012,10,dayToInt(group['day']),group['time'].to_i,0,0,DateTime.now.offset)
      reg.groups << Group.new({
        :name => group['name'],
        :when => whenDate,
      })
    end
    params['tutors'].each do |tutor|
      tutorData=tutor[1]
      reg.tutors << Tutor.new({
        :name => tutorData['name'],
        :email => tutorData['email']
      })
    end
    reg.save
    
    @title=reg.title
    @url=CONFIG[:baseurl]+"/manage/#{reg.id}/#{reg.access_code}"
    Pony.mail CONFIG[:pony_opts].merge({
      :to => reg.email,
      :subject => "Tutorial Assignment for #{reg.title}",
      :body => erb(:email_register)
    })
           
    "#{reg.id}/#{reg.access_code}"
  end
  
  run!
end

