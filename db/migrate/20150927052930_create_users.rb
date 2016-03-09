class CreateUsers < ActiveRecord::Migration
  def change
    create_table :users do |t|
      t.text :mail
      t.text :username
      t.string :password_digest
      t.text :sec_q
      t.text :sec_a
      t.timestamps null: false
    end
  end
end
