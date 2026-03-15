class CreatePayments < ActiveRecord::Migration[7.1]
  def change
    create_table :payments do |t|
      t.references :translation, null: false, foreign_key: true

      t.string :pix_txid, index: { unique: true }
      t.string :pix_copia_e_cola
      t.text :pix_qr_code_base64

      t.decimal :amount_brl, precision: 10, scale: 2, null: false
      t.integer :status, default: 0

      t.datetime :paid_at
      t.datetime :expires_at

      t.timestamps
    end
  end
end
