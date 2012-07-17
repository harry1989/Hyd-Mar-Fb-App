require "sinatra"
require 'koala'
require 'rubygems'                                                                                                                                                                             
require 'sinatra'
#require 'data_mapper'
#require 'dm-migrations'
require 'dm-core'
require 'dm-timestamps'

enable :sessions
set :raise_errors, false
set :show_exceptions, false

# Scope defines what permissions that we are asking the user to grant.
# In this example, we are asking for the ability to publish stories
# about using the app, access to what the user likes, and to be able
# to use their pictures.  You should rewrite this scope with whatever
# permissions your app needs.
# See https://developers.facebook.com/docs/reference/api/permissions/
# for a full list of permissions
FACEBOOK_SCOPE = ''

unless ENV["FACEBOOK_APP_ID"] && ENV["FACEBOOK_SECRET"]
  abort("missing env vars: please set FACEBOOK_APP_ID and FACEBOOK_SECRET with your app credentials")
end

before do
  # HTTPS redirect
  if settings.environment == :production && request.scheme != 'https'
    redirect "https://#{request.env['HTTP_HOST']}"
  end
end

helpers do
  def host
    request.env['HTTP_HOST']
  end

  def scheme
    request.scheme
  end

  def url_no_scheme(path = '')
    "//#{host}#{path}"
  end

  def url(path = '')
    "#{scheme}://#{host}#{path}"
  end

  def authenticator
    @authenticator ||= Koala::Facebook::OAuth.new(ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_SECRET"], url("/auth/facebook/callback"))
  end

end

configure :development, :test do
  DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite://#{Dir.pwd}/appdatabase")                                                                                                       
end 

configure :production do
  DataMapper.setup(:default, ENV['DATABASE_URL'] || "postgres://localhost/appdatabase")                                                                                                       
end

class User
  include DataMapper::Resource
  property :id,           Serial
  property :name,         String,  :required => true  
  property :facebook_id,  String,  :required => true  
  property :updated_at,   DateTime
  
  has n, :teamapprovedusers
  has n, :approvedteams, :model => 'Team', :through => :teamapprovedusers

  has n, :teamjoinedusers
  has n, :joinedteams, :model => 'Team', :through => :teamjoinedusers
end

class Team
  include DataMapper::Resource
  property :id,           Serial
  property :name,         String,  :required => true  
  property :description,   Text
  has 1,  'User', :owner
  
  has n, :teamapprovedusers
  has n, :approvedusers, :model => 'User', :through => :teamapprovedusers

  has n, :teamjoinedusers
  has n, :joinedusers, :model => 'User', :through => :teamjoinedusers
end

class Teamapproveduser
  include DataMapper::Resource
  belongs_to :approvedteam, :model => 'Team',  :key => true
  belongs_to :approveduser, :model => 'User',  :key => true
end

class Teamjoineduser
  include DataMapper::Resource
  belongs_to :joinedteam, :model => 'Team',  :key => true
  belongs_to :joineduser, :model => 'User',  :key => true
end

# the facebook session expired! reset ours and restart the process
error(Koala::Facebook::APIError) do
  session[:access_token] = nil
  redirect "/auth/facebook"
end

DataMapper.auto_upgrade!


get "/" do
  # Get base API Connection
  @graph  = Koala::Facebook::API.new(session[:access_token])

  # Get public details of current application
  @app  =  @graph.get_object(ENV["FACEBOOK_APP_ID"])

  if session[:access_token]
    @user    = @graph.get_object("me")
    app_user = User.first_or_create(:name => @user['name'], :facebook_id => @user['id'])
    @friends = User.all
    @photos  = @graph.get_connections('me', 'photos')
    @likes   = @graph.get_connections('me', 'likes').first(4)
    @teams   = Team.all

    # for other data you can always run fql
    @friends_using_app = @graph.fql_query("SELECT uid, name, is_app_user, pic_square FROM user WHERE uid in (SELECT uid2 FROM friend WHERE uid1 = me()) AND is_app_user = 1")
  end
  erb :index
end

# used by Canvas apps - redirect the POST to be a regular GET
post "/" do
  redirect "/"
end

# View a team
get '/team/:id' do
  @team = Team.get(params[:id])
  erb :team
end

# used to close the browser window opened to post to wall/send to friends
get "/close" do
  "<body onload='window.close();'/>"
end


get "/create_team" do
  erb :new_team 
end


get "/sign_out" do
  session[:access_token] = nil
  redirect '/'
end


get "/auth/facebook" do
  session[:access_token] = nil
  redirect authenticator.url_for_oauth_code(:permissions => FACEBOOK_SCOPE)
end

get '/auth/facebook/callback' do
	session[:access_token] = authenticator.get_access_token(params[:code])
	@graph  = Koala::Facebook::API.new(session[:access_token])
	@user   = @graph.get_object("me")
	user    = User.first_or_create(:name => @user['name'], :facebook_id => @user['id'])
	puts "Created the new user %s", %(user['name'])
	redirect '/'
end


# View a team
get '/team/:id' do
  @task = Team.get(params[:id])
  erb :team
end
