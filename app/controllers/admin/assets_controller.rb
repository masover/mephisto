class Admin::AssetsController < Admin::BaseController
  before_filter :find_asset, :except => [:index, :new, :create, :latest, :search, :upload, :clear_bucket]

  def index
    search_assets 20
    @recent = []
    4.times { @recent << @assets.shift }
    @recent.compact!
    
    respond_to do |format|
      format.html
      format.js
    end
  end
  
  def new
    @asset = Asset.new
  end

  def create
    @asset = site.assets.build(params[:asset])
    @asset.save!
    redirect_to assets_path
  rescue ActiveRecord::RecordInvalid
    render :action => 'new'
  end

  def update
    @asset.attributes = params[:asset]
    @asset.save!
    redirect_to assets_path
  rescue ActiveRecord::RecordInvalid
    render :action => 'edit'
  end

  def latest
    @assets = site.assets.find(:all, :order => 'created_at desc', :limit => 6)
    render :update do |page|
      page['latest-assets'].replace_html :partial => 'widget', :collection => @assets
    end
  end
  
  def search
    search_assets 6
    render :update do |page|
      page['search-assets'].replace_html :partial => 'widget', :collection => @assets
    end
  end

  def upload
    article_id = params[:asset].delete(:article_id)
    @asset = site.assets.build(params[:asset])
    @asset.save!
    article_id ? 
      redirect_to(:controller => 'articles', :action => 'edit', :id => article_id) :
      redirect_to(:controller => 'articles', :action => 'new')
  end

  def destroy
    @asset.destroy
    redirect_to assets_path
    flash[:notice] = "Deleted '#{@asset.filename}'"
  end

  # rjs
  def add_bucket
    (session[:bucket] ||= {})[@asset.public_filename] = [@asset.public_filename(:tiny), "#{@asset.title} \n #{@asset.tags.join(', ')}"]
  end

  def clear_bucket
    session[:bucket] = nil
  end

  protected
    def find_asset
      @asset = site.assets.find(params[:id])
    end

    def search_assets(limit)
      @types  = params[:filter].blank? ? [] : params[:filter].keys
      @asset_pages = Paginator.new self, count_by_conditions, limit, params[:page]
      @assets = @types.any? ?
        site.assets.find_all_by_content_types(@types, :all, search_options) :
        site.assets.find(:all, search_options)
    end

    def search_options
      search_conditions.merge(:order => 'created_at desc', :limit => @asset_pages.items_per_page, :offset => @asset_pages.current.offset)
    end

    def search_conditions
      return @search_conditions if @search_conditions
      unless params[:q].blank?
        params[:q].downcase!
        params[:q] << '%'
      end
      
      @search_conditions =
        returning :conditions => [] do |options|
          options[:include] = []
          unless params[:q].blank?
            params[:conditions] = { :title => true, :tags => true } if params[:conditions].blank?
            if params[:conditions].has_key?(:title)
              options[:conditions] << Asset.send(:sanitize_sql, ['(LOWER(assets.title) LIKE :q or LOWER(assets.filename) LIKE :q)', {:q => params[:q]}])
            end
            
            if params[:conditions].has_key?(:tags)
              options[:include] << :tags
              options[:conditions] << Asset.send(:sanitize_sql, ["(taggings.taggable_type = 'Asset' and tags.name IN (?))", Tag.parse(params[:q])])
            end
          end
        
          if options[:conditions].blank?
            options.delete(:conditions)
          else
            options[:conditions] *= ' OR ' 
          end
          
          options.delete(:include) if options[:include].empty?
        end
    end
    
    def count_by_conditions
      type_conditions = @types.blank? ? nil : Asset.types_to_conditions(@types.dup).join(" OR ")
      @count_by_conditions ||= search_conditions[:conditions].blank? ? site.assets.count(:all, :conditions => type_conditions) :
        Asset.count( 
        :joins =>  search_conditions[:joins], 
        :conditions => "site_id = #{site.id} #{type_conditions && "and #{type_conditions}"} AND #{search_conditions[:conditions]}", 
        :include => search_conditions[:include])
    end
end
