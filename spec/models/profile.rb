class Profile < ActiveRecord::Base
  class Settings < Torque::PostgreSQL::Attributes::Struct
    attribute :theme, :string, default: 'light'
    attribute :notifications, :boolean, default: true
    attribute :tags

    validates :theme, inclusion: { in: %w[light dark] }, allow_nil: true
  end

  class Bio < Torque::PostgreSQL::Attributes::Struct
    attribute :headline, :string
    attribute :website, :string
  end

  class Preview < Torque::PostgreSQL::Attributes::Struct
    attribute :label, :string
    attribute :url, :string

    validates :url, presence: true
  end

  class Snippet < Torque::PostgreSQL::Attributes::Struct
    attribute :title, :string
    attribute :body, :string
  end

  struct_for :settings, Settings, delegate: %i[theme]
  struct_for :bio, Bio
  struct_for :previews, Preview, array: true
  struct_for :snippets, Snippet
end
