class CreateSpreeProductImports < ActiveRecord::Migration[5.1]
  def change
    create_table :spree_product_imports do |t|
      t.attachment :variants_csv
      t.attachment :products_csv

      t.timestamps null: false
    end
  end
end
