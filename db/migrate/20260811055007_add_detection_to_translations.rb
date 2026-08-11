class AddDetectionToTranslations < ActiveRecord::Migration[8.1]
  def change
    add_column :translations, :detected_title, :string
    add_column :translations, :detected_summary, :text
  end
end
