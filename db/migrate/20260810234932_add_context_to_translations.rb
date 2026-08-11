class AddContextToTranslations < ActiveRecord::Migration[8.1]
  def change
    add_column :translations, :context, :text
  end
end
