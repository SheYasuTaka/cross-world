class CreateWords < ActiveRecord::Migration
  def change
    create_table :words do |t|
      t.text :main
      t.text :tags
      t.text :about
      t.text :parents
      t.text :children
      t.text :faq, :limit => 65536
      t.timestamps null: false
    end
  end
end
