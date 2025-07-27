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

version = 5

return if ActiveRecord::Migrator.current_version == version
ActiveRecord::Schema.define(version: version) do
  self.verbose = false

  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  # Custom schemas used in this database.
  create_schema "internal", force: :cascade

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "content_status", ["created", "draft", "published", "archived"]
  create_enum "specialties", ["books", "movies", "plays"]
  create_enum "roles", ["visitor", "assistant", "manager", "admin"]
  create_enum "conflicts", ["valid", "invalid", "untrusted"]
  create_enum "types", ["A", "B", "C", "D"]

  create_table "geometries", force: :cascade do |t|
    t.point   "point"
    t.line    "line"
    t.lseg    "lseg"
    t.box     "box"
    t.path    "closed_path"
    t.path    "open_path"
    t.polygon "polygon"
    t.circle  "circle"
  end

  create_table "time_keepers", force: :cascade do |t|
    t.daterange "available"
    t.tsrange   "period"
    t.tstzrange "tzperiod"
    t.interval  "th"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name"
  end

  create_table "videos", force: :cascade do |t|
    t.bigint   "tag_ids", array: true
    t.string   "title"
    t.string   "url"
    t.enum     "type", enum_type: :types
    t.enum     "conflicts", enum_type: :conflicts, array: true
    t.jsonb    "metadata"
    # t.column   "pieces", :int4multirange
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "authors", force: :cascade do |t|
    t.string   "name"
    t.string   "type"
    t.enum     "specialty", enum_type: :specialties
  end

  create_table "categories", force: :cascade do |t|
    t.integer  "parent_id"
    t.string   "title"
  end

  create_table "texts", force: :cascade do |t|
    t.integer  "user_id"
    t.string   "content"
    t.enum     "conflict", enum_type: :conflicts
  end

  create_table "comments", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "comment_id"
    t.integer "video_id"
    t.text    "content", null: false
    t.string  "kind"
    t.index ["user_id"], name: "index_comments_on_user_id", using: :btree
    t.index ["comment_id"], name: "index_comments_on_comment_id", using: :btree
  end

  create_table "courses", force: :cascade do |t|
    t.integer         "category_id"
    t.string          "title", null: false
    t.interval        "duration"
    t.enum            "types", enum_type: :types, array: true
    t.search_language "lang", null: false, default: 'english'
    t.search_vector   "search_vector", columns: :title, language: :lang
    t.datetime        "created_at", null: false
    t.datetime        "updated_at", null: false
  end

  create_table "images", force: :cascade, id: false do |t|
    t.string "file"
  end

  create_table "posts", force: :cascade do |t|
    t.integer       "author_id"
    t.integer       "activity_id"
    t.string        "title"
    t.text          "content"
    t.enum          "status", enum_type: :content_status
    t.search_vector "search_vector", columns: %i[title content]
    t.index ["author_id"], name: "index_posts_on_author_id", using: :btree
  end

  create_table "items", force: :cascade do |t|
    t.string   "name"
    t.bigint   "tag_ids", array: true, default: "{1}"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.string   "name", null: false
    t.enum     "role", enum_type: :roles, default: :visitor
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", schema: "internal", force: :cascade do |t|
    t.string   "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_internal_users_on_email", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.integer  "author_id"
    t.string   "title"
    t.boolean  "active"
    t.enum     "kind", enum_type: :types
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "questions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string   "title"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "activity_books", force: :cascade, inherits: :activities do |t|
    t.text     "description"
    t.string   "url"
    t.boolean  "activated"
  end

  create_table "activity_posts", force: :cascade, inherits: [:activities, :images] do |t|
    t.integer  "post_id"
    t.string   "url"
    t.integer  "activated"
  end

  create_table "activity_post_samples", force: :cascade, inherits: :activity_posts

  create_table "question_selects", force: :cascade, inherits: :questions do |t|
    t.string  "options", array: true
  end

  # create_table "activity_blanks", force: :cascade, inherits: :activities

  # create_table "activity_images", force: :cascade, inherits: [:activities, :images]

  add_foreign_key "posts", "authors"
rescue Exception => e
  byebug
  raise
end

ActiveRecord::Base.connection.schema_cache.clear!
