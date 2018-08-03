require 'csv'
require "down"

class Spree::ProductImport < ActiveRecord::Base

  # CONSTANTS
  # IMPORTABLE_PRODUCT_FIELDS = [:slug, :name, :price, :cost_price, :available_on, :shipping_category, :tax_category, :taxons, :option_types, :description].to_set
  # Maybe just get headers from CSV files
  IMPORTABLE_PRODUCT_FIELDS = ["EAN", "ItemUnit", "Nettopris", "Bruttopris", "LangProduktBeskrivelse", "ProduktGruppe", "ProduktID", 
                               "Varetekst1", "Varetekst2", "Synonyms", "ProduktGruppeTekst", "Weight", "SupName", "SupplierURL", 
                               "ProductURL", "PakkeAntal", "Billede", "Kategori1", "Kategori2", "Kategori3", "Kategori4", 
                               "Specifications", "SupplierProductNumber", "DisplayName", "Brand"].to_set
  IMPORTABLE_VARIANT_FIELDS = [:sku, :slug, :cost_price, :cost_currency, :tax_category, :stock_items_count, :option_values].to_set

  # Not directly assignable to the product
  RELATED_PRODUCT_FIELDS = [:taxons, :option_types].to_set
  RELATED_VARIANT_FIELDS = [:slug, :option_values].to_set

  IMAGE_EXTENSIONS = ['.jpg', '.png', '.gif'].to_set

  OPTIONS_SEPERATOR = '->'

  # attachments
  has_attached_file :products_csv

  # validations
  validates_attachment :products_csv, content_type: { content_type: ["text/csv", "text/plain"] }

  validates :products_csv, presence: true

  # callbacks
  after_commit :start_product_import

  private

  def start_product_import
    import_product_data if products_csv.present?
  end

  #handle_asynchronously :start_product_import# ??????????????

  def import_product_data
    failed_import = []
    Spree::Product.destroy_all if Spree::Product.all.any?
    CSV.foreach(products_csv.path, encoding: 'iso-8859-1', headers: true, col_sep: ';') do |product_data|
      unless import_product_from(product_data)
        failed_import << product_data
      end
    end
  end
  
  def import_product_from(product_data_row)
    begin
      ActiveRecord::Base.transaction do
        product = create_or_update_product(product_data_row)
        set_missing_product_properties(product, product_data_row)
        add_taxons(product, product_data_row)
        add_images(product, product_data_row["Billede"])
      end
    rescue Exception
      false
    else
      true
    end
  end

  def create_or_update_product(product_data_row)
    product_properties = build_properties_hash(product_data_row, IMPORTABLE_PRODUCT_FIELDS, RELATED_PRODUCT_FIELDS)
    product_properties[:tax_category] = Spree::TaxCategory.first
    product_properties[:shipping_category] = Spree::ShippingCategory.first
    product = Spree::Product.find_or_initialize_by(slug: product_properties[:slug])
    product.update!(product_properties)
    product
  end
  
  def build_properties_hash(data_row, attributes_to_read, related_attr)
    properties_hash = {}
    copieable_attributes = (attributes_to_read - related_attr)
    
    data_row.each do |key, value|
      if copieable_attributes.include? key
        case key
        when "DisplayName"
          properties_hash[:name] = value
          properties_hash[:meta_title] = value
          properties_hash[:slug] = value.parameterize
        when "Nettopris"
          properties_hash[:cost_price] = value.gsub(',','.')
        when "Bruttopris"
          properties_hash[:price] = value.gsub(',','.')
        when "LangProduktBeskrivelse"
          properties_hash[:description] = value
          properties_hash[:meta_description] = value
        when "EAN"
          properties_hash[:sku] = value
        when "Weight"
          properties_hash[:weight] = value.gsub(',','.')
        end
      end
    end
    properties_hash[:available_on] = Time.now.utc.to_s
    properties_hash[:promotionable] = true
    
    properties_hash
  end
  
  def set_missing_product_properties(product, product_data_row)
    product_data_row.each do |key, value|
      case key
      # Product Properties in correct order from CSV
      when "ItemUnit"
        property = Spree::Property.find_or_create_by!(name: "item_unit", presentation: "Item Unit")
        product_property = Spree::ProductProperty.find_or_create_by!(value: value, product: product, property: property)
      when "SupplierURL"
        property = Spree::Property.find_or_create_by!(name: "supplier_url", presentation: "Supplier URL")
        product_property = Spree::ProductProperty.find_or_create_by!(value: value, product: product, property: property)
      when "ProductURL"
        property = Spree::Property.find_or_create_by!(name: "product_url", presentation: "Product URL")
        product_property = Spree::ProductProperty.find_or_create_by!(value: value, product: product, property: property)
      when "PakkeAntal"
        property = Spree::Property.find_or_create_by!(name: "package_count", presentation: "Package Count")
        product_property = Spree::ProductProperty.find_or_create_by!(value: value, product: product, property: property)
      when "Specifications"
        property = Spree::Property.find_or_create_by!(name: "specifications", presentation: "Specifications")
        product_property = Spree::ProductProperty.find_or_create_by!(value: value, product: product, property: property)
      when "Brand"
        property = Spree::Property.find_or_create_by!(name: "brand", presentation: "Brand")
        product_property = Spree::ProductProperty.find_or_create_by!(value: value, product: product, property: property)
      end
    end
  end

  def add_taxons(product, product_data_row)
    first_level = Spree::Taxon.find_by(name: product_data_row["Kategori1"])
    second_level = first_level.children.find_by(name: product_data_row["Kategori2"])
    third_level = second_level.children.find_by(name: product_data_row["Kategori3"])
    fourth_level = third_level.children.find_by(name: product_data_row["Kategori4"])
    
    taxons = [first_level, second_level, third_level, fourth_level]
    
    product.assign_attributes(taxons: taxons)
  end

  def build_csv_from_failed_import_list(failed_import)
    CSV.generate do |csv|
      failed_import.each do |data_row|
        csv << data_row
      end
    end
  end

  def add_images(product, image_dir)
    return unless image_dir
    
    tempfile = Down.download(image_dir)
    image = Spree::Image.create!(attachment: { io: tempfile, filename: tempfile.original_filename })
    product.images << image
  end
end
