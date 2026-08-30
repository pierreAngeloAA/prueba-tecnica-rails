# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_08_30_154100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "line_item_directives", force: :cascade do |t|
    t.bigint "line_item_id", null: false
    t.string "directive_type", limit: 10, null: false
    t.string "unit_uid", limit: 64
    t.string "key", limit: 64, null: false
    t.text "value"
    t.string "source", limit: 16, null: false
    t.integer "version", null: false
    t.datetime "created_at", null: false
    t.index ["line_item_id", "key", "version"], name: "idx_line_item_directives_by_key"
    t.index ["line_item_id", "unit_uid", "key", "version"], name: "idx_line_item_directives_by_unit"
    t.check_constraint "directive_type::text = 'header'::text AND unit_uid IS NULL OR directive_type::text = 'unit'::text AND unit_uid IS NOT NULL", name: "chk_line_item_directives_scope"
  end
end
