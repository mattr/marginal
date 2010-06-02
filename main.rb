require 'rubygems'
require 'sinatra'
require 'haml'
require 'builder'
require 'candy'
require 'redcloth'
require 'coderay'

class Post
  include Candy::Piece
  def summary
    body.match(/(.{200}.*?\n)/m).to_s
  end
  def url
    "#{Site.url}/archive/#{slug}"
  end
end
class Posts
  include Candy::Collection
  collects :post
end

configure do
  require 'ostruct'
  Site = OpenStruct.new({
    :key    => 'admin',
    :val    => 'changeme', # replace with a random string to prevent attacks.
    :pass   => 'password', # make this something more secure while you're at it.
    :url    => 'mydomain.com',
    :disqus => 'mysite', # unset this if you don't want comments.
    :title  => 'My Awesome Marginal Blog',
    :author => 'My Name'
  })
  # Assumes that the database is running on localhost:21027
  # To see how to set additional parameters, see ''.
  Post.db = 'marginal'
end

error do
  e = request.env['sinatra.error']
  puts e.to_s
  puts e.backtrace.join("\n")
  "Application error"
end

helpers do
  # Is the user logged in?
  def admin?
    request.cookies[Site.key] == Site.val
  end
  
  # Make sure the user is logged in.
  def auth
    halt [ 401, "Not Authorized" ] unless admin?
  end
  
  # Make the separate tags into links to categories.
  def tagify(tags)
    tags.map { |a| "<a href=\"/tag/#{tag}\">#{tag}</a>" }.join('&nbsp')
  end
  
  # Make a uniqe slug to reference the post using the title and incremental counter for repeated titles.
  def slugify(title)
    slug = title.downcase.gsub(/ /, '-').gsub(/[^a-z0-9\-]/, '').squeeze('-')
    if (count = Posts.slug(/#{slug}/).count) > 0
      slug << "-#{count}"
    end
    slug
  end
  
  # Format the body into HTML.
  def html(text)
    RedCloth.new(text.gsub(/\<code( lang="(.+?)")?\>(.+?)\<\/code\>/m) { "<notextile>#{CodeRay.scan($3, $2).div(:css => :class)}</notextile>" }).to_html
  end
end

# In-file stylesheet
get "/site.css" do
  content_type 'text/css', :charset => "utf-8"
  sass :site
end

# Index/root shows 5 most recent posts
get "/" do
  haml :posts, :locals => { :posts => Posts.limit(5).sort(:created, :desc) }
end

# Atom feed
get "/feed" do
  content_type 'application/xml', :charset => 'utf-8'
  @posts = Posts.limit(20).sort(:created, :desc)
  builder :feed, :layout => false
end

# Tagged posts
get "/tag/:tag" do
  haml :posts, :locals => { :posts => Posts.tag(params[:tag]).sort(:created, :desc) }
end

# Older posts, just dump everything in reverse chronological order.
get "/archive" do
  haml :posts, :locals => { :posts => Posts.sort(:created, :desc) }
end

# Single post
get "/archive/:slug" do
  haml :post, :locals => { :post => Post.slug(params[:slug]) }
end

## Admin

# Login prompt
get "/auth" do
  haml :auth
end

# Login action
post "/auth" do
  response.set_cookie(Site.key, Site.val) if params[:pass] == Site.pass
  redirect "/"
end

# New post
get "/new" do
  auth
  haml :edit, :locals => {:url => "/create"}
end

# Create post
post "/create" do
  auth
  post = Post.new(title: params[:title], slug: slugify(params[:title]), tags: params[:tags].split(' ').compact, body: params[:body], created: Time.now, updated: Time.now)
  redirect "/"
end

# Edit post
get "/archive/:slug/edit" do
  auth
  haml :edit, :locals => { :url => "/archive/#{params[:slug]}", :post => Post.slug(params[:slug]) }
end

# Update post
post "/archive/:slug" do
  auth
  post = Post.slug(params[:slug])
  post.title    = params[:title]
  post.tags     = params[:tags].split(' ').compact
  post.body     = params[:body]
  post.updated  = Time.now
  redirect "/archive/#{slug}"
end

__END__

@@ feed
xml.instruct!
xml.feed "xmlns" => "http://www.w3.org/2005/Atom" do
  xml.title Site.title
  xml.id Site.url
  xml.updated posts.first.created.iso8601 if @posts.any?
  xml.author { xml.name Site.author }
  
  @posts.each do |post|
    xml.entry do
      xml.title post.title
      xml.link "rel" => "alternate", "href" => post.url
      xml.id post.url
      xml.published post.created.iso8601
      xml.updated post.updated.iso8601
      xml.author { xml.name Site.author }
      xml.summary html(post.summary), "type" => "html"
      xml.content html(post.body), "type" => "html"
    end
  end
end

@@ layout
!!! 5
%html{:lang => "en"}
  %head
    %meta{:charset => "utf-8"}
    %title= Site.title
    %link{:href => "/feed", :rel => "alternate", :type => "application/xml"}
    %link{:href => "/site.css", :rel => "stylesheet", :type => "text/css"}
  %body
    #page
      #head
        %h1
          %a{:href => "http://#{Site.url}"}= Site.title
        %h2= Site.author
      #content
        = yield
        .archive
          [&nbsp;
          %a{:href => "/archive"} Older Posts
          &nbsp;]
      .clear
      #footer
        ="&copy; #{Date.today.year} #{Site.author}"

@@ posts
- if admin?
  %a{:href => "/new"} New Post
- posts.each do |post|
  .post
    %h1
      %a{:href => "/archive/#{post.slug}"}= post.title
    .tags= tagify(post.tags)
    .body= html(post.summary)

@@ post
.post
  - if admin?
    %a.edit_post{:href => "/#{post.slug}/edit"} Edit
  %h1= post.title
  .tags= tagify(post.tags)
  .date= post.created.strftime('%d %B %Y')
  .body= html(post.body)
  #comments
    - if Site.disqus
      #disqus_thread
      %script{:type => "text/javascript", :src => "http://disqus.com/forums/#{Site.disqus}/embed.js"}
      %noscript
        %a{:href => "http://#{Site.disqus}.disqus.com/?url=ref"}View the discussion thread.
      %a{:href => "http://disqus.com", :class => "dsq-brlink"}
        blog comments powered by
        %span.logo-disqus Disqus

@@ edit
%form{:action => url, :method => "POST"}
  %input{:type => "text", :id => "title", :name => "title", :value => (post.title rescue '')}
  %input{:type => "text", :id => "tags", :name => "tags", :value => (post.tags.join(' ') rescue '')}
  %textarea{:id => "body", :name => "body", :value => (post.body rescue '')}
  %input{:type => "submit", :value => "Save"}

@@ auth
%form{:action => "/auth", :method => "POST"}
  %label{:for => "pass"} Password
  %br
  %input{:type => "password", :id => "pass", :name => "pass"}

@@ site
body
  :background #292929
  :color #fefefe
  :font-family "helvetica neue", arial, sans-serif
  :font-size 13px
#page
  :width 960px
  :padding 10px
  :margin auto
h1, h1 > a
  :font-size 27px
  :color #fefefe
  :text-decoration none
  :text-transform lowercase
h2
  :font-size 19px
  :font-variant italic
a, a:visited
  :color #404040
  :text-decoration underline
a:hover
  :text-decoration none
.clear
  :clear both
  :float none
#content
  :background #fff
  :color #222
  :border 1px solid #666
  :padding 10px
  h1
    :font-size 21px
    :margin-left 30px
  .date
    :float left
  .archive
    :text-align center
  form > *
    :display block
    :color #404040
    :padding 2px
    :font-size 14px
    :width 100%
    :margin-bottom 10px
  input[type="text"], input[type="password"]
    :padding 2px
    :font-size 16px
  textarea
    :height 300px
  .new_post, .edit_post
    :float right
#footer
  :font-size 10px
  :text-align center