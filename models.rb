require 'mysql2'


#unless ENV['RACK_ENV'] == 'production'
#    ActiveRecord::Base.establish_connection('sqlite3:db/development.db')
#end

class User < ActiveRecord::Base
    has_secure_password
    validates :mail,
        presence: true,
        format:{with:/.+@.+/}
    validates :password,
        length:{in: 8..32}
end

class Word < ActiveRecord::Base
    validates :main,
        length:{minimum: 2}
end


