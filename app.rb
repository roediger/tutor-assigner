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
  
  # pairs.each do |a,b|
  #   tutors.each do |tutor|
  #     cplex+= " + [ 1000 t#{tutor.id}g#{a} * t#{tutor.id}g#{b} ]"
  #   end
  # end

  post '/manage/:id/:access_code/solve' do
    reg=Registration.first(:id => params[:id],:access_code => params[:access_code])
    raise unless reg
    
    groups=reg.groups
    tutors=reg.tutors    
    
    class Var
      attr_accessor :tutors,:groups
      
      def initialize(tutors,groups)
        @tutors=[tutors].flatten
        @groups=[groups].flatten
      end
      
      def prefs
        tutors.map { |t,g| t.preferences.all(:group => groups) }.flatten.reject{ |p| p.nil? }
      end
      
      def name
        # XXX make this a unique auto increment counter in production
        "t#{tutors.map{|t|t.id}.join("t")}g#{groups.map{|g|g.id}.join("g")}"
      end
      
      def weight
        if prefs.length == 0 || prefs.find{|p|p.weight==0} then 
          0
        else
          (prefs.reduce(0.0) { |sum,p| sum+p.weight } / (prefs.length)).to_i
        end
      end
    end
    
    cplex = "Maximize\n"
    
    # Build objective function: add all variables while considering their weight
    vars = tutors.product(groups).map { |tutor,group| Var.new(tutor,group) }
    vars.delete_if { |var| var.weight == 0 }
    cplex+= " obj: -1000000 slack1 + " + vars.map { |var| "#{var.weight} #{var.name}" }.join(" + ") + "\n"
    
    # Add variables for consecutive groups
    pairs=[]
    lastCluster={ :slot => DateTime.now, :groups => [] }
    groups.to_a.sort { |a,b| a.when<=>b.when }.chunk { |g| g.when }.each do |slot,groups|
      pairs += lastCluster[:groups].product(groups) if lastCluster[:slot]+(2.0/24.0) == slot
      lastCluster={ :slot => slot, :groups => groups }
    end
        
    cplex+= "Subject To\n"
        
    # Solve so that all groups are assigned, rest goes into an extremely expensive slack variable
    cplex+= " all: "+vars.map { |var| var.name }.join(" + ") + " + slack1 = #{2*tutors.length}\n"
    
    # At most one tutor for each group
    groups.each do |group|
      groupVars=vars.find_all { |var| var.groups.find{ |g| g==group } }.map{ |var| var.name }
      cplex+= " g#{group.id}: " + groupVars.join(" + ") + " <= 1\n" if groupVars.length > 0
    end
        
    # At most two groups per tutor
    tutors.each do |tutor|
      tutorVars=vars.find_all { |var| var.tutors.find{ |t| t==tutor } }.map{ |var| "#{var.groups.length} #{var.name}" }
      cplex+= " t#{tutor.id}: " + tutorVars.join(" + ") + " <= 2\n" if tutorVars.length > 0
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

    IO.write("out.lp",cplex)
    out,solution,status=Open3.capture3("glpsol --lp /dev/stdin -o /dev/stderr",:stdin_data=>cplex)
    IO.write("debug.sol",solution)
    puts out
    
    # out,err,status=Open3.capture3("gurobi_cl ResultFile=out.sol out.lp")
    # solution=IO.read("out.sol")
    # 
    # result=Hash.new
    # solution.split(/\n/).each do |line|
    #   next unless line.match(/^t\d+.*?[\s\t]+1/)
    #   
    #   cols=line.split(/[\s\t]+/)
    #   m=cols[0].match(/t(\d+)g(\d+)/)
    #   t=m[1].to_i
    #   g=m[2].to_i
    #   result[Group.first(:id => g).name]=Tutor.first(:id => t).name
    # end
    # p result

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

