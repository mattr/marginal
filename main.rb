# Chances are you've got at least 5 of these installed already...
%w{ rubygems sinatra candy haml builder redcloth coderay }.each { |gemname| require gemname }
class Post # Document class, used to return a single result.
  include Candy::Piece
  
  def summary # Shorter body text
    body.match(/(.{200}.*?\n)/m).to_s
  end
  
  def url # Full url for use in rss feed link
    "#{Site.url}/post/#{slug}"
  end
end
class Posts; include Candy::Collection; collects :post; end # Collection class, used to return multiple results.

configure do
  require 'ostruct'
  Site = OpenStruct.new({
    :key  => 'admin',             # Cookie key
    :val  => 'randomstring',      # Change this to something random; this is stored as the cookie value.
    :pass => 'password',          # While your at it, make this a little more secure.
    :url  => 'mysite.com',        # The base URL to which this blog is deployed.
    :disq => 'mysite',            # The disqus reference to your site. Just remove to disable comments.
    :name => 'My Marginal Blog',  # The title of your blog.
    :me   => 'My Name'            # Your name.
  })
  # Assumes localhost:27017; see http://rdoc.info/projects/SFEley/candy for more config options
  Post.db = "marginal"
end

error do # Error handling
  e = request.env['sinatra.error']
  puts e.to_s
  puts e.backtrace.join "\n"
  "Application error"
end

helpers do # Helper methods for views, parameter handling and authentication.
  def admin? # Checks if the user is logged in.
    request.cookies[Site.key] == Site.val
  end
  
  def auth # Restricts access to admin pages.
    halt [401, "Not authorized"] unless admin?
  end
  
  def link(tags) # Turns each of the elements in the array to an anchor tag.
    tags.each { |tag| "<a href=\"/tag/#{tag}\">#{tag}</a>" }
  end
  
  def slugify(title) # Turn the title into a slug with auto-increment for repeats.
    slug = title.downcase.gsub(/ /, '-').gsub(/[^a-z0\-]/, '').squeeze('-')
    slug << "-#{count}" if (count = Posts.slug(/#{slug}/).count) > 0
    slug
  end
  
  def html(text) # Parse the body text using RedCloth, with CodeRay for code syntax highlighting.
    RedCloth.new( text.gsub(/\<code( lang="(.+?)")?\>(.+?)\<\/code\>/m) { "<notextile>#{CodeRay.scan($3, $2).div(:css => :class)}</notextile>"} ).to_html
  end
end

## STYLESHEET
get "/site.css" do
  content_type "text/css", :charset => "utf-8"
  sass :site
end

## PUBLIC PAGES
get "/" do # Root, shows 5 most recent blog posts in reverse chronologial order.
  haml :posts, :locals => { :posts => Posts.limit(5).sort(:created, :desc) }
end

get "/feed" do # Shows the 20 most recent blog posts in reverse chronological order (atom format).
  content_type "application/xml", :charset => "utf-8"
  @posts = Posts.limit(20).sort(:created, :desc)
  builder :feed, :layout => false
end

get "/tag/:tag" do # Lists all posts with a particular tag in reverse chronological order.
  haml :posts, :locals => { :posts => Posts.tag(params[:tag]).sort(:created, :desc) }
end

get "/posts" do # Lists all posts in reverse chronological order. This is the closest we get to an archive.
  haml :posts, :locals => {:posts => Posts.sort(:created, :desc) }
end

get "/posts/:slug" do # Displays a particular post.
  haml :post, :locals => { :post => Post.slug(params[:slug]) }
end

## ADMIN PAGES
get "/auth" do # Login prompt.
  haml :auth
end

post "/auth" do # Login validation.
  response.set_cookie(Site.key, Site.val) if params[:pass] == Site.pass
  redirect "/"
end

get "/new" do # Form to create new post.
  auth
  haml :edit, :locals => { :url => "/create" }
end

post "/create" do # Creates a new post.
  auth
  Post.new(title: params[:title], slug: slugify(params[:title]), tags: params[:tags].split(' ').compact, body: params[:body], created: Time.now, updated: Time.now)
end

get "/posts/:slug/edit" do # Form to edit an existing post.
  auth
  haml :edit => { :url => "/posts/#{params[:slug]}", :post => Post.slug(params[:slug]) }
end

post "/posts/:slug" do # Updates an existing post.
  auth
  post = Post.slug(params[:slug])
  post.title = params[:title]
  post.tags = params[:tags].split(' ')
  post.body = params[:body]
  post.updated = Time.now
  redirect "/posts/#{params[:slug]}"
end

# To delete posts, you have to go in to the console.

__END__

@@ feed
xml.instruct!
xml.feed "xmlns" => "http://www.w3.org/2005/Atom" do
  xml.title Site.name
  xml.id Site.url
  xml.updated @posts.first.created.iso8601 if @posts.any?
  xml.author { xml.name Site.me }
  @posts.each do |post|
    xml.entry do
      xml.title post.title
      xml.link "rel" => "alternate", "href" => post.url
      xml.id post.url
      xml.published post.created.iso8601
      xml.updated post.updated.iso8601
      xml.author { xml.name Site.me }
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
    %title= Site.name
    %link{:rel => "stylesheet", :type => "text/css", :href => "site.css", :media => "screen,projection"}
  %body
    #page
      #header
        %h1= Site.name
        %h2= Site.me
      #content
        = yield
        #archive= "[&nbsp;<a href=\"/posts\">Older Posts</a>&nbsp;]"
      #footer
        = "&copy; #{Date.today.year} #{Site.me}"

@@ posts
- if admin?
  %a.new{:href => "/new"} New Post
- posts.each do |post|
  .post
    %h2
      %a{:href => "/posts/#{post.slug}"} Post.title
    .date= "#{post.created.strftime('%d')}<br />#{post.created.strftime('%m')}"
    .tags= link(post.tags)
    .body= html(post.summary)
    %a.more{:href => "/posts/#{post.slug}"} More...

@@ post
.post
  - if admin?
    %a.edit{:href => "/posts/#{post.slug}/edit"} Edit
  %h2= post.title
  .date= "#{post.created.strftime('%d')}<br />#{post.created.strftime('%m')}"
  .tags= link(post.tags)
  .body= html(post.body)
  #comments
    - if Site.disq
      #disqus_thread
        %script{:type => "text/javascript", :src => "http://disqus.com/forums/#{Site.disq}/embed.js"}
        %noscript
          %a{:href => "http://#{Site.disq}.disqus.com/?url=ref"} View the discussion thread.
        %a{:href => "http://disqus.com", :class => "dsq-brlink"}
          blog comments powered by
          %span.logo-disqus Disqus

@@ edit
%form{:action => url, :method => "POST"}
  %input#title{:type => "text", :name => "title", :value => (post.title rescue ''), :overlay => "Title"}
  %input#tags{:type => "text", :name => "tags", :value => (post.tags.join(' ') rescue ''), :overlay => "Tags"}
  %textarea#body{:name => "body", :value => (post.body rescue '')}
  %input#commit{:type => "submit", :name => "commit", :value => "Save"}

@@ auth
%form{:action => "/auth", :method => "POST"}
  %input#password{:type => "password", :name => "pass", :prefill => "Password"}
  %input#commit{:type => "submit", :name => "commit", :value => "Login"}

@@ site
body
  :background #292929
  :color #fefefe
  :font 13px/1.3 "helvetica neue", helvetica, arial, sans-serif
#page
  :width 940px
  :padding 10px
  :margin auto
#header
  h1
    :font-size 25px
    :text-transform lowercase
    a
      :color #fefefe
      :text-decoration none
  h2
    :font-size 21px
    :font-variant italic
#content
  :background #fff
  :color #222
  :text-align justify
  :padding 10px
  :border 1px solid #666
  a, a:visited
    :color #404040
    :text-decoration underline
  a:hover
    :color #202020
    :text-decoration none
  h2
    :font-size 17px
    :padding 5px
    :margin-left 30px
    a
      :text-decoration none
    a:hover
      :text-decoration underline
  .date
    :float left
  .new, .edit
    :float right
  #archive
    :text-align center
  input
    :padding 2px
    :width 80%
    #title
      :font-size 15px
  textarea
    :width 80%
    :height 40
#footer
  :text-align center
  :font-size 11px
