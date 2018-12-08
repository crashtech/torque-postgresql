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

begin
  version = 34

  raise SystemExit if ActiveRecord::Migrator.current_version == version
  ActiveRecord::Schema.define(version: version) do
    self.verbose = false

    # These are extensions that must be enabled in order to support this database
    enable_extension "plpgsql"

    # These are user-defined types used on this database
    create_enum "content_status", ["created", "draft", "published", "archived"], force: :cascade
    create_enum "specialties", ["books", "movies", "plays"], force: :cascade
    create_enum "roles", ["visitor", "assistant", "manager", "admin"], force: :cascade
    create_enum "conflicts", ["valid", "invalid", "untrusted"], force: :cascade
    create_enum "types", ["A", "B", "C", "D"], force: :cascade

    create_table "authors", force: :cascade do |t|
      t.string   "name"
      t.string   "type"
      t.enum     "specialty", subtype: :specialties
    end

    create_table "texts", force: :cascade do |t|
      t.string   "content"
      t.enum     "conflict",  subtype: :conflicts
    end

    create_table "comments", force: :cascade do |t|
      t.integer "user_id",    null: false
      t.integer "comment_id"
      t.text    "content",    null: false
      t.string  "kind"
      t.index ["user_id"], name: "index_comments_on_user_id", using: :btree
      t.index ["comment_id"], name: "index_comments_on_comment_id", using: :btree
    end

    create_table "courses", force: :cascade do |t|
      t.string   "title",      null: false
      t.interval "duration"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "images", force: :cascade, id: false do |t|
      t.string "file"
    end

    create_table "posts", force: :cascade do |t|
      t.integer  "author_id"
      t.integer  "activity_id"
      t.string   "title"
      t.text     "content"
      t.enum     "status",    subtype: :content_status
      t.index ["author_id"], name: "index_posts_on_author_id", using: :btree
    end

    create_table "users", force: :cascade do |t|
      t.string   "name",       null: false
      t.enum     "role",                    subtype: :roles, default: :visitor
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "activities", force: :cascade do |t|
      t.integer  "author_id"
      t.string   "title"
      t.boolean  "active"
      t.enum     "kind",                    subtype: :types
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    create_table "activity_books", force: :cascade, inherits: :activities do |t|
      t.text     "description"
      t.string   "url"
    end

    create_table "activity_posts", force: :cascade, inherits: [:activities, :images] do |t|
      t.integer  "post_id"
      t.string   "url"
    end

    create_table "activity_post_samples", force: :cascade, inherits: :activity_posts

    # create_table "activity_blanks", force: :cascade, inherits: :activities

    # create_table "activity_images", force: :cascade, inherits: [:activities, :images]

    add_foreign_key "posts", "authors"
  end
rescue SystemExit
end
