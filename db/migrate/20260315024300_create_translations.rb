class CreateTranslations < ActiveRecord::Migration[7.1]
  def change
    create_table :translations do |t|
      t.string :access_token, null: false, index: { unique: true }
      t.string :original_filename, null: false
      t.string :target_language, default: "pt-BR"
      t.string :model_used, default: "gpt-4.1-mini"

      t.integer :subtitle_count, default: 0
      t.integer :tokens_input, default: 0
      t.integer :tokens_output, default: 0
      t.decimal :cost_ai, precision: 10, scale: 6, default: 0.0
      t.decimal :cost_ai_brl, precision: 10, scale: 2, default: 0.0
      t.decimal :cost_user, precision: 10, scale: 2, default: 0.0

      t.integer :status, default: 0
      t.text :error_message
      t.float :processing_time

      t.timestamps
    end
  end
end
