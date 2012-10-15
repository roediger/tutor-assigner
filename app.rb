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
require 'singleton'


require './config.rb'


class App < Sinatra::Base
  set :logging, :true
  set :port, 9999
  set :root, File.dirname(__FILE__)
  register Sinatra::AssetPack


  #DataMapper::Model.raise_on_save_failure = true
  DataMapper::Logger.new(STDOUT, :debug)
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
    has 1,:meta_preference
  end
  
  class MetaPreference
    include DataMapper::Resource
    property :id,Serial
    property :priority, Integer, :default => 1
    property :count, Integer, :default => 2
    property :consecutive, Boolean, :default => true
    #property :sameday, Boolean    
    #property :sameslot, Boolean
    belongs_to :tutor
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
      t.attributes.merge({
        :gcount => t.preferences.all(:weight => 1).length,
        :meta_preference => t.meta_preference
      })
    })
    @groups=JSON.generate(reg.groups)
    erb :manage
  end

  post '/manage/:id/:access_code/update' do
    reg=Registration.first(:id => params[:id],:access_code => params[:access_code])
    raise unless reg
    
    tutor=Tutor.first(:id=>params['tutor_id'])
    tutor.meta_preference=MetaPreference.create unless tutor.meta_preference
    tutor.meta_preference.count=params['count'].to_i
    tutor.meta_preference.consecutive=params['consecutive']=="true"
    tutor.save
    
    JSON.generate(tutor)
  end

  post '/manage/:id/:access_code/solve' do
    reg=Registration.first(:id => params[:id],:access_code => params[:access_code])
    raise unless reg
    
    groups=reg.groups
    tutors=reg.tutors    
    
    class PrefCache
      include Singleton
      
      def initialize 
        prefs=Preference.all
        @cache=Hash.new
        prefs.each do |pref|
          @cache["#{pref.tutor.id}-#{pref.group.id}"]=pref
        end
      end
      
      def get(tutor,group)
        @cache["#{tutor.id}-#{group.id}"]
      end
    end

    
    class Var
      attr_accessor :tutors,:groups
      
      def initialize(tutors,groups)
        @tutors=[tutors].flatten
        @groups=[groups].flatten
      end
      
      def prefs
        tutors.map { |t| groups.map { |g| PrefCache.instance.get(t,g) } }.flatten.reject{ |p| p.nil? }
        #tutors.map { |t,g| t.preferences.all(:group => groups) }.flatten.reject{ |p| p.nil? }
      end
      
      def name
        # XXX make this a unique auto increment counter in production
        "t#{tutors.map{|t|t.id}.join("t")}g#{groups.map{|g|g.id}.join("g")}"
      end
      
      def weight
        if prefs.length < groups.length || prefs.find{|p|p.weight==0} then 
          0
        else
          (prefs.reduce(0.0) { |sum,p| sum+p.weight } / (prefs.length)).to_i * (groups.length>1 ? 1000 : 1)
        end
      end
    end
        
    cplex = "Maximize\n"
        
    # Build objective function: add all variables while considering their weight
    vars = tutors.product(groups).map { |tutor,group| Var.new(tutor,group) }
    
    # Find all pairs of consecutive groups
    pairs=[]
    lastCluster={ :slot => DateTime.now, :groups => [] }
    groups.to_a.sort { |a,b| a.when<=>b.when }.chunk { |g| g.when }.each do |slot,groups|
      pairs += lastCluster[:groups].product(groups) if lastCluster[:slot]+(2.0/24.0) == slot
      lastCluster={ :slot => slot, :groups => groups }
    end    
    
    # Add variables for pairs
    tutors.each do |tutor|
      vars += pairs.map { |groups| Var.new(tutor,groups)} if tutor.meta_preference && tutor.meta_preference.consecutive
    end
    vars.delete_if { |var| var.weight == 0 }
    
    cplex+= " obj: -1000000 slack1 + " + vars.map { |var| "#{var.weight} #{var.name}" }.join(" + ") + "\n"
                        
    cplex+= "Subject To\n"
        
    # Solve so that all groups are assigned, rest goes into an extremely expensive slack variable
    cplex+= " all: "+vars.map { |var| "#{var.groups.length} #{var.name}" }.join(" + ") + " + slack1 = #{2*tutors.length}\n"
    
    # At most one tutor for each group
    groups.each do |group|
      groupVars=vars.find_all { |var| var.groups.find{ |g| g==group } }.map{ |var| var.name }
      cplex+= " g#{group.id}: " + groupVars.join(" + ") + " <= 1\n" if groupVars.length > 0
    end
        
    # At most two groups per tutor
    tutors.each do |tutor|
      tutorVars=vars.find_all { |var| var.tutors.find{ |t| t==tutor } }.map{ |var| "#{var.groups.length} #{var.name}" }
      cplex+= " t#{tutor.id}: " + tutorVars.join(" + ") + " <= #{tutor.meta_preference.count||2}\n" if tutorVars.length > 0
    end
    
    # Group by tutor, group by slot, <= 1
    slotIndex=0
    tutors.each do |tutor|
      groups.group_by { |group| group.when }.each do |slot,groups|
        # find all variables concerning the tutor and at least one of the mentioned groups
        slotVars=vars.find_all { |var| var.tutors.find { |t| t == tutor } and var.groups.find { |g| groups.find { |g2| g2==g } } }
        next unless slotVars.length > 1
        cplex+= " s#{slotIndex}t#{tutor.id}: " + slotVars.map { |var| var.name }.join(" + ") + " <= 1\n"
        slotIndex+=1
      end
    end
    
    # Set all variables to binary
    cplex+= "Binary " + vars.map { |var| var.name }.join(" ")+"\n"

    IO.write("debug.lp",cplex)
    out,solution,status=Open3.capture3("time glpsol --lp /dev/stdin -o /dev/stderr",:stdin_data=>cplex)
    IO.write("debug.sol",solution)
    puts out
    
    result=Hash.new
    solution.split(/\n/).each do |line|
      cols=line.split(/[\s\t]+/)
      if cols[4]=="1" then
        var = vars.find { |v| v.name == cols[2] }
        var.groups.each { |group| result[group.name]=var.tutors[0].name } if var         
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

