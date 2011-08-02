require "spec_helper"

describe CouchRest::Model::Views do

  class Unattached < CouchRest::Model::Base
    property :title
    property :questions
    property :professor
    view_by :title

    # Force the database to always be nil
    def self.database
      nil
    end
  end

  describe "ClassMethods" do
    # NOTE! Add more unit tests!

    describe "#view" do

      it "should not alter original query" do
        options = { :database => DB }
        view = Article.view('by_date', options)
        options[:database].should eql(DB)
      end

    end

    describe "#has_view?" do
      it "should check the design doc" do
        Article.design_doc.should_receive(:has_view?).with(:test).and_return(true)
        Article.has_view?(:test).should be_true
      end
    end

    describe "#can_reduce_view?" do
      it "should check if view has a reduce method" do
        Article.design_doc.should_receive(:can_reduce_view?).with(:test).and_return(true)
        Article.can_reduce_view?(:test).should be_true
      end
    end
  end

  describe "a model with simple views and a default param" do
    before(:all) do
      Article.all.map{|a| a.destroy(true)}
      Article.database.bulk_delete
      written_at = Time.now - 24 * 3600 * 7
      @titles = ["this and that", "also interesting", "more fun", "some junk"]
      @titles.each do |title|
        a = Article.new(:title => title)
        a.date = written_at
        a.save
        written_at += 24 * 3600
      end
    end
    it "should return the matching raw view result" do
      view = Article.by_date :raw => true
      view['rows'].length.should == 4
    end
    it "should not include non-Articles" do
      Article.database.save_doc({"date" => 1})
      view = Article.by_date :raw => true
      view['rows'].length.should == 4
    end
    it "should return the matching objects (with default argument :descending => true)" do
      articles = Article.by_date
      articles.collect{|a|a.title}.should == @titles.reverse
    end
    it "should allow you to override default args" do
      articles = Article.by_date :descending => false
      articles.collect{|a|a.title}.should == @titles
    end
    it "should allow you to create a new view on the fly" do
      lambda{Article.by_title}.should raise_error 
      Article.view_by :title
      lambda{Article.by_title}.should_not raise_error 
    end
  end

  describe "another model with a simple view" do
    before(:all) do
      reset_test_db!
      %w{aaa bbb ddd eee}.each do |title|
        Course.new(:title => title).save
      end
    end
    it "should make the design doc upon first query" do
      Course.by_title 
      doc = Course.design_doc
      doc['views']['all']['map'].should include('Course')
    end
    it "should can query via view" do
      # register methods with method-missing, for local dispatch. method
      # missing lookup table, no heuristics.
      view = Course.view :by_title
      designed = Course.by_title
      view.should == designed
    end
    it "should get them" do
      rs = Course.by_title 
      rs.length.should == 4
    end
    it "should yield" do
      courses = []
      Course.view(:by_title) do |course|
        courses << course
      end
      courses[0]["doc"]["title"].should =='aaa'
    end
    it "should yield with by_key method" do
      courses = []
      Course.by_title do |course|
        courses << course
      end
      courses[0]["doc"]["title"].should =='aaa'
    end
  end

  describe "find a single item using a view" do
    before(:all) do
      reset_test_db!
      %w{aaa bbb ddd eee}.each do |title|
        Course.new(:title => title, :active => (title == 'bbb')).save
      end
    end

    it "should return single matched record with find helper" do
      course = Course.find_by_title('bbb')
      course.should_not be_nil
      course.title.should eql('bbb') # Ensure really is a Course!
    end

    it "should return nil if not found" do
      course = Course.find_by_title('fff')
      course.should be_nil
    end

    it "should peform search on view with two properties" do
      course = Course.find_by_title_and_active(['bbb', true])
      course.should_not be_nil
      course.title.should eql('bbb') # Ensure really is a Course!
    end

    it "should return nil if not found" do
      course = Course.find_by_title_and_active(['bbb', false])
      course.should be_nil
    end

    it "should raise exception if view not present" do
      lambda { Course.find_by_foobar('123') }.should raise_error(NoMethodError)
    end

    it "should perform a search directly with specific key" do
      course = Course.first_from_view('by_title', 'bbb')
      course.title.should eql('bbb')
    end

    it "should perform a search directly with specific key with options" do
      course = Course.first_from_view('by_title', 'bbb', :reverse => true)
      course.title.should eql('bbb')
    end

    it "should perform a search directly with range" do
      course = Course.first_from_view('by_title', :startkey => 'bbb', :endkey => 'eee')
      course.title.should eql('bbb')
    end

    it "should perform a search for first when reduce method present" do
      course = Course.first_from_view('by_active')
      course.should_not be_nil
    end

  end
  
  describe "a ducktype view" do
    before(:all) do
      reset_test_db!
      @id = DB.save_doc({:dept => true})['id']
    end
    it "should setup" do
      duck = Course.get(@id) # from a different db
      duck["dept"].should == true
    end
    it "should make the design doc" do
      @as = Course.by_dept
      @doc = Course.design_doc
      @doc["views"]["by_dept"]["map"].should_not include("couchrest")
    end
    it "should not look for class" do
      @as = Course.by_dept
      @as[0]['_id'].should == @id
    end
  end
  
  describe "a model class with database provided manually" do
    before(:all) do
      reset_test_db!
      @db = DB 
      %w{aaa bbb ddd eee}.each do |title|
        u = Unattached.new(:title => title)
        u.database = @db
        u.save
        @first_id ||= u.id
      end
    end
    it "should barf on all if no database given" do
      lambda{Unattached.all}.should raise_error
    end
    it "should query all" do
      rs = Unattached.all :database => @db
      rs.length.should == 4
    end
    it "should barf on query if no database given" do
      lambda{Unattached.view :by_title}.should raise_error
    end
    it "should make the design doc upon first query" do
      Unattached.by_title :database => @db
      doc = Unattached.design_doc
      doc['views']['all']['map'].should include('Unattached')
    end
    it "should merge query params" do
      rs = Unattached.by_title :database=>@db, :startkey=>"bbb", :endkey=>"eee"
      rs.length.should == 3
    end
    it "should query via view" do
      view = Unattached.view :by_title, :database=>@db
      designed = Unattached.by_title :database=>@db
      view.should == designed
    end
    it "should yield" do
      things = []
      Unattached.view(:by_title, :database=>@db) do |thing|
        things << thing
      end 
      things[0]["doc"]["title"].should =='aaa'
    end
    it "should yield with by_key method" do
      things = []
      Unattached.by_title(:database=>@db) do |thing|
        things << thing
      end
      things[0]["doc"]["title"].should =='aaa'
    end
    it "should return nil on get if no database given" do
      Unattached.get("aaa").should be_nil
    end
    it "should barf on get! if no database given" do
      lambda{Unattached.get!("aaa")}.should raise_error
    end
    it "should get from specific database" do
      u = Unattached.get(@first_id, @db)
      u.title.should == "aaa"
    end
    it "should barf on first if no database given" do
      lambda{Unattached.first}.should raise_error
    end
    it "should get first" do
      u = Unattached.first :database=>@db
      u.title.should =~ /\A...\z/
    end
    
    it "should get last" do
      u = Unattached.last :database=>@db
      u.title.should == "aaa"
    end

  end
  
  describe "a model with a compound key view" do
    before(:all) do
      Article.by_user_id_and_date.each{|a| a.destroy(true)}
      Article.database.bulk_delete
      written_at = Time.now - 24 * 3600 * 7
      @titles = ["uniq one", "even more interesting", "less fun", "not junk"]
      @user_ids = ["quentin", "aaron"]
      @titles.each_with_index do |title,i|
        u = i % 2
        a = Article.new(:title => title, :user_id => @user_ids[u])
        a.date = written_at
        a.save
        written_at += 24 * 3600
      end
    end
    it "should create the design doc" do
      Article.by_user_id_and_date rescue nil
      doc = Article.design_doc
      doc['views']['by_date'].should_not be_nil
    end
    it "should sort correctly" do
      articles = Article.by_user_id_and_date
      articles.collect{|a|a['user_id']}.should == ['aaron', 'aaron', 'quentin', 
        'quentin']
      articles[1].title.should == 'not junk'
    end
    it "should be queryable with couchrest options" do
      articles = Article.by_user_id_and_date :limit => 1, :startkey => 'quentin'
      articles.length.should == 1
      articles[0].title.should == "even more interesting"
    end
  end
  
  describe "with a custom view" do
    before(:all) do
      @titles = ["very uniq one", "even less interesting", "some fun", 
        "really junk", "crazy bob"]
      @tags = ["cool", "lame"]
      @titles.each_with_index do |title,i|
        u = i % 2
        a = Article.new(:title => title, :tags => [@tags[u]])
        a.save
      end
    end
    it "should be available raw" do
      view = Article.by_tags :raw => true
      view['rows'].length.should == 5
    end
    
    it "should be default to :reduce => false" do
      ars = Article.by_tags
      ars.first.tags.first.should == 'cool'
    end
    
    it "should be raw when reduce is true" do
      view = Article.by_tags :reduce => true, :group => true
      view['rows'].find{|r|r['key'] == 'cool'}['value'].should == 3
    end
  end
  
  # TODO: moved to Design, delete
  describe "adding a view" do
    before(:each) do
      reset_test_db!
      Article.by_date
      @original_doc_rev = Article.stored_design_doc['_rev']
      @design_docs = Article.database.documents :startkey => "_design/", :endkey => "_design/\u9999"
    end
    it "should not create a design doc on view definition" do
      Article.view_by :created_at
      newdocs = Article.database.documents :startkey => "_design/", :endkey => "_design/\u9999"
      newdocs["rows"].length.should == @design_docs["rows"].length
    end
    it "should create a new version of the design document on view access" do
      Article.view_by :updated_at
      Article.by_updated_at
      @original_doc_rev.should_not == Article.stored_design_doc['_rev']
      Article.design_doc["views"].keys.should include("by_updated_at")
    end
  end
  
  describe "accessing data by custom view" do
    it "should return the row" do
      art = Article.create! :title => 'a title', :user_id => 'bob', :time => Time.now - 1.minute
      rows = Article.by_user_id_and_time :startkey => ['bob'], :endkey => ['bob',Time.now]
      rows.length.should == 1
      rows.first.should == art
    end
    
    it "should not return the row" do
      art = Article.create! :title => 'a title', :user_id => 'bob', :time => Time.now + 1.minute
      rows = Article.by_user_id_and_time :startkey => ['bob'], :endkey => ['bob',Time.now]
      rows.length.should == 0
    end
  end

end
