require 'csv'

class Spree::ProductImport < ActiveRecord::Base

  # CONSTANTS
  IMPORTABLE_PRODUCT_FIELDS = [:slug, :name, :price, :cost_price, :available_on, :shipping_category,
                               :tax_category, :taxons, :option_types, :description].to_set
  IMPORTABLE_VARIANT_FIELDS = [:sku, :slug, :cost_price, :cost_currency, :tax_category,
                               :stock_items_count, :option_values].to_set

  # Not directly assignable to the product
  RELATED_PRODUCT_FIELDS = [:taxons, :option_types].to_set
  RELATED_VARIANT_FIELDS = [:slug, :option_values].to_set

  IMAGE_EXTENSIONS = ['.jpg', '.png', '.gif'].to_set

  OPTIONS_SEPERATOR = '->'

  # attachments
  has_attached_file :variants_csv
  has_attached_file :products_csv

  # validations
  validates_attachment :variants_csv, :products_csv, content_type: { content_type: ["text/csv", "text/plain"] }

  validates :variants_csv, presence: true, unless: -> { products_csv.present? }
  validates :products_csv, presence: true, unless: -> { variants_csv.present? }

  # callbacks
  after_commit :start_product_import

  private

  def start_product_import
    import_product_data if products_csv.present?
    import_variant_data if variants_csv.present?
  end

  #handle_asynchronously :start_product_import ??????????????

  def import_product_data
    failed_import = []
    CSV.foreach(products_csv.path, headers: true, header_converters: :symbol) do |product_data|
      unless import_product_from(product_data)
        failed_import << product_data
      end
    end
    if failed_import.empty?
      Spree::ProductImportMailer.import_data_success_email(id, "products_csv").deliver_later
    else
      failed_import_csv = build_csv_from_failed_import_list(failed_import)
      Spree::ProductImportMailer.import_data_failure_email(id, "products_csv", failed_import_csv).deliver_later
    end
  end

  def import_variant_data
    failed_import = []
    CSV.foreach(variants_csv.path, headers: true, header_converters: :symbol) do |variant_data|
      unless import_variant_from(variant_data)
        failed_import << variant_data
      end
    end
    if failed_import.empty?
      Spree::ProductImportMailer.import_data_success_email(id, "variants_csv").deliver_later
    else
      failed_import_csv = build_csv_from_failed_import_list(failed_import)
      Spree::ProductImportMailer.import_data_failure_email(id, "variants_csv", failed_import_csv).deliver_later
    end
  end

  def create_or_update_product(product_data_row)
    product_properties = build_properties_hash(product_data_row, IMPORTABLE_PRODUCT_FIELDS, RELATED_PRODUCT_FIELDS)
    product_properties[:tax_category] = Spree::TaxCategory.find_or_create_by!(name: product_properties[:tax_category])
    product_properties[:shipping_category] = Spree::ShippingCategory.find_or_create_by!(name: product_properties[:shipping_category])
    product = Spree::Product.find_or_initialize_by(slug: product_properties[:slug])
    product.update!(product_properties)
    product
  end

  def set_missing_product_options(product, product_data_row)
    product_data_row[:option_types].to_s.split(',').each do |option|
      option_name = option.strip
      option_type = Spree::OptionType.find_or_initialize_by(name: option_name)
      option_type.presentation = option_name unless option_type.presentation
      option_type.save!
      unless product.option_types.include? option_type
        product.option_types << option_type
      end
    end
  end

  def add_taxons(product, product_data_row)
    product_data_row[:taxons].to_s.split(',').each do |taxon|
      product.taxons.find_or_create_by!(name: taxon)
    end
  end

  def import_product_from(product_data_row)
    begin
      ActiveRecord::Base.transaction do
        product = create_or_update_product(product_data_row)
        set_missing_product_options(product, product_data_row)
        add_taxons(product, product_data_row)
        add_images(product, product_data_row[:images])
      end
    rescue Exception
      false
    else
      true
    end
  end

  def create_or_update_variant(product, variant_data_row)
    variant_properties = build_properties_hash(variant_data_row, IMPORTABLE_VARIANT_FIELDS, RELATED_VARIANT_FIELDS)
    variant_properties[:tax_category] = Spree::TaxCategory.find_or_create_by!(name: variant_properties[:tax_category])
    variant = product.variants.find_or_initialize_by(sku: variant_properties[:sku])
    variant.update!(variant_properties)
    variant
  end

  def set_variant_options(variant, product, variant_data_row)
    variant_data_row[:option_values].to_s.split(',').each do |option_pair|
      option_name, option_value = option_pair.split(OPTIONS_SEPERATOR)
      option_type = product.option_types.find_by(name: option_name)
      option_value = Spree::OptionValue.find_or_initialize_by(name: option_value, option_type: option_type)
      unless option_value.presentation
        option_value.presentation = option_value
      end
      option_value.save!
      unless variant.option_values.include? option_value
        variant.option_values << option_value
      end
    end
  end

  def import_variant_from(variant_data_row)
    begin
      ActiveRecord::Base.transaction do
        product = Spree::Product.find_by(slug: variant_data_row[:slug])
        raise 'product does not exist' unless product
        variant = create_or_update_variant(product, variant_data_row)
        set_variant_options(variant, product, variant_data_row)
        add_images(variant, variant_data_row[:images])
      end
    rescue Exception
      false
    else
      true
    end
  end

  def build_csv_from_failed_import_list(failed_import)
    CSV.generate do |csv|
      failed_import.each do |data_row|
        csv << data_row
      end
    end
  end

  def build_properties_hash(data_row, attributes_to_read, related_attr)
    properties_hash = {}
    copieable_attributes = (attributes_to_read - related_attr)

    data_row.each do |key, value|
      if copieable_attributes.include? key
        properties_hash[key] = value
      end
    end
    properties_hash
  end

  def add_images(model_obj, image_dir)
    return unless image_dir
    load_images(image_dir).each do |image_file|
      model_obj.images << Spree::Image.create(attachment: File.new("#{ image_dir }/#{ image_file }", 'r'))
    end
  end

  def load_images(image_dir)
    if Dir.exists?(image_dir)
      Dir.open(image_dir).entries.select do |entry|
        IMAGE_EXTENSIONS.include? File.extname(entry).downcase
      end
    else
      raise 'Image directory not found'
    end
  end

end
