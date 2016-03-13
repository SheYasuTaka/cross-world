#! ruby -Ku
# -*- coding: utf-8 -*-

require 'bundler/setup'
Bundler.require
require 'sinatra/reloader' if development?
require './models.rb'
require 'cgi'

require 'active_record'
require 'mysql2'
require 'sinatra'

ActiveRecord::Base.configurations = YAML.load_file('config/database.yml')
ActiveRecord::Base.establish_connection('development')

configure do
    enable :sessions
end

class Japanese
    def initialize(str = "")
        @filter = /[^ァ-ンヴー]+/
        @unify = unify(str)
        @isJap = (@unify !~ @filter)
    end
    def unify(str)
        return str.tr('ぁ-ん', 'ァ-ン').tr('ァィゥェォッャュョヰヱヵヶ', 'アイウエオツヤユヨイエカケ')
    end
    def filter
        @filter
    end
    def isJap
        @isJap
    end
    def split_from(str)
        unify(str).split(@filter).reject{|e| e.empty?}
    end
    def unified
        @unify
    end
end

def split_with_blank (str)
    str.split(/[[:blank:]]+/)
end

def escape_for_regexp (str)
    str.gsub(/(?=[\\*+.?{}()\[\]^$\-\|])/, "\\")
end

def str_to_hex (str)
    str.codepoints.map{|v| v.to_s(0x10).rjust(4,'0')}.join('')
    # example: "こいしちゃんはあずかった 要求はない, 1時間後に殺す"
    # =======> "305330443057306130833093306f3042305a304b3063305f00\
    # =======>  2089816c42306f306a3044002c00200031664295935f8c306b\
    # =======>  6bba3059"
end

def hex_to_str (hex)
    hex.split(/(.{4})/).map{|v| v.empty? ? '' : v.to_i(0x10).chr(Encoding::UTF_8)}.join('')
    # example: "305330443057306130833093306f3042305a304b3063305f00\
    # example:  2089816c42306f306a3044002c00200031664295935f8c306b\
    # example:  6bba3059"
    # =======> "こいしちゃんはあずかった 要求はない, 1時間後に殺す"
end

def court_regexp (str)
    japanese = Japanese.new()
    chars = japanese.unify(str).split('')
    chars.map!{ |char|
        if char !~ japanese.filter
           str_to_hex(char)
        else case char
        when '+', '＋'
            '(.{4})+'
        when '*', '＊'
            '(.{4})*'
        when '.', '?', '？'
            '(.{4})'
        else
            raise "invalid"
        end
        end
    }
    # str.gsub!(/\+＋/, '.+')
    # str.gsub!(/\*＊/, '.*')
    # str.gsub!(/\./, '(.{4})')
    p chars
    '^' + chars.join('') + '$'
end

def finder_for_Word (conditions)
    con = ActiveRecord::Base.connection
    query = "SELECT * FROM `words`"
    where = []
    conditions.each { |key, val|
        key = '`' + key.to_s + '`'
        if val.class.to_s === 'String'
            escaped = con.quote(val)
            where.push(key + " = " + escaped)
        else
            data = val[:inc]
            if data
                data = data.class.to_s === 'Array' ? data : [data]
                data.reject{|e| e.empty?}.each { |str|
                escaped = con.quote(str)
                    where.push(key + " REGEXP " + escaped)
                }
            end
            data = val[:exc]
            if data
                data = data.class.to_s === 'Array' ? data : [data]
                data.reject{|e| e.empty?}.each { |str|
                escaped = con.quote(str)
                    where.push(key + " NOT REGEXP " + escaped)
                }
            end
        end
    }
    if !where.empty?
        query << " WHERE " << where.join(' AND ')
    end
    p query
    query
end

def tags_to_view (data)
    data = (data.class.to_s === 'Array' ? data : [data])
    data.map{ |item|
        '<a href="/search?regexp=*&inctags=' + item + '">' + item + '</a>'
    }.join('&nbsp;')
end

def words_to_view (data)
    data = (data.class.to_s === 'Array' ? data : [data])
    data.map{ |item|
        '<a href="/word/' + item + '">' + item + '</a>'
    }.join('&nbsp;')
end

get '/' do
    session[:f] = nil
    erb :index
end

get '/signup' do
    erb :sign_up
end

post '/goto_sup' do
    redirect '/signup'
end

post '/signup' do
    @fail = ""
    if User.find_by(username: params[:un])
        @fail << "The username was used<br>"
    end
    if params[:pw] != params[:pw_conf]
        @fail << "The passwords didn't match<br>"
    end
    if !@fail.empty?
        erb :sign_up
    else
        @user = User.create(
            username: params[:un],
            mail: params[:mail],
            password: params[:pw],
            password_confirmation: params[:pw_conf],
            sec_q: params[:forgot_q],
            sec_a: params[:forgot_a]
        )
        if @user
            session[:user]=@user.id
        end
        redirect '/'
    end
end

get '/sin' do
    user = User.find_by(username: params[:un])
    if user && user.authenticate(params[:pw])
        session[:user] = user.id
    end
    redirect'/'
end

get '/signout' do
    session.clear
    redirect'/'
end

get '/forgot/:step' do
    if params[:step] == 'conf' then
        session[:f] = nil
        erb :forgot1
    elsif session[:f] == nil then
        redirect '/'
    else
        case params[:step]
        when 'watchword'
            erb :forgot2
        when 'reset'
            erb :forgot3
        else
            redirect '/'
        end
    end
end

post '/reset_password' do
    User.find(session[:f]).update(
        password: params[:pw],
        password_confirmation: params[:pw_conf]
    )
    redirect '/'
end

post '/forgot/:step' do
    case params[:step]
    when 'conf'
        user = User.find_by(username: params[:un])
        if user == nil then
            @fail = "The username is invalid<br>"
            erb :forgot1
        else
            session[:f] = user.id
            redirect '/forgot/watchword'
        end
    when 'watchword'
        if session[:f] == nil || params[:ans] == nil then
            redirect '/'
        elsif params[:ans] != User.find(session[:f]).sec_a then
            @fail = "Incorrect<br>"
            erb :forgot2
        else
            redirect '/forgot/reset'
        end
    when 'reset'
    end
end

get '/add' do
    erb :add
end

post '/add' do
    @fail = ""
    @caution = ""
    japanese = Japanese.new()
    main = japanese.unify(params[:main])
    if main.empty? then
        @fail << "Input main word<br>"
    elsif main.length <= 1 then
        @fail << "Invalid word for crossword<br>"
    else
        encoded_main = str_to_hex(main)
        if Word.find_by(main: encoded_main) then
        @fail << "The word has already been registerd<br>"
        end
    end
    if !@fail.empty?
        erb :add
    else
        about = params[:about]
        tags = split_with_blank(params[:tags]).map{|item|
            CGI.escapeHTML(item)
        }
        parents = japanese.split_from(params[:parents]).map{|item|
            CGI.escapeHTML(item)
        }
        children = japanese.split_from(params[:children]).map{|item|
            CGI.escapeHTML(item)
        }
        Word.create(
            main: encoded_main,
            tags: tags.join(' '),
            about: about,
            parents: parents.join(' '),
            children: children.join(' '),
            faq: ""
        )
        redirect ('/word/' << CGI.escape(main))
    end
end

get '/word/:id' do
    japanese = Japanese.new()
    begin
        @request_word = japanese.unify(params[:id])
        if japanese.filter =~ @request_word
            raise "unmatch for lang"
        end
        word = Word.find_by(main: str_to_hex(@request_word))
        if !word
            raise "not found"
        end
        p @request_word
        @word_id = word.id
        @about = CGI.escapeHTML(word.about)
        @tags = tags_to_view(split_with_blank(word.tags))
        @par = words_to_view(split_with_blank(word.parents))
        @chl = words_to_view(split_with_blank(word.children))
        @ques = word.faq.split(/\n/)
    rescue
        p $!.to_s
        @fail = $!.to_s
    end
    erb :wordview
end

get '/search' do
    @regexp = params[:regexp] || ""
    @inctags = split_with_blank(params[:inctags] || "")
    @exctags = split_with_blank(params[:exctags] || "")
    begin
        courted = court_regexp(@regexp)
        query = finder_for_Word({
            main: {
                inc: courted
            },
            tags: {
                inc: @inctags,
                exc: @exctags
            }
        })
        @result = Word.find_by_sql(query).sort{ |l, r| l <=> r}
    rescue
    @fail = $!.to_s
    end
    erb :srch_rslt
end

get '/newq/:word' do
    @word = params[:word]
    erb :newq
end

post '/newq/:word' do
    @fail = ""
    word = str_to_hex(params[:word])
    user = Word.find_by(main: word)
    if !user then
        redirect '/'
    else
        ques = params[:question]
        if user.faq.empty?
            ques = "\n" + ques
        end
        user.faq << ques
        isSaved = user.save
        if !isSaved then
            @fail << "Sorry, but It seems not enter anymore<br>"
            erb :newq
        else
            redirect ('/word/' << CGI.escape(hex_to_str(word)))
        end
    end
end
