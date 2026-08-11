class CreateMatches < ActiveRecord::Migration[8.1]
  def change
    create_table :matches do |t|
      t.string :title, null: false
      t.json :state, null: false

      t.timestamps
    end
  end
end
