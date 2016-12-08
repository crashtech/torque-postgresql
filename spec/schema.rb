# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 0) do
  self.verbose = false

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  # These are user defined custom column types used on this database
  create_enum :content_status, ["created", "draft", "published", "archived"], force: :cascade

  create_table "posts", force: :cascade do |t|
    t.string   "title"
    t.text     "content"
    t.enum     "status",                  enumerator: :content_status
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

end
