require 'spec_helper'

module GithubPivotalFlow
  describe Story do
    let(:fake_git) { double('Git').as_null_object }

    def stub_git_branches
      allow(Git).to receive(:get_config).with(GithubPivotalFlow::KEY_MASTER_BRANCH, :inherited) { 'master' }
      allow(Git).to receive(:get_config).with(GithubPivotalFlow::KEY_VALIDATION_BRANCH, :inherited) { 'validation' }
      allow(Git).to receive(:get_config).with(GithubPivotalFlow::KEY_DEVELOPMENT_BRANCH, :inherited) { 'development' }
      allow(Git).to receive(:get_config).with(GithubPivotalFlow::KEY_FEATURE_PREFIX, :inherited) { 'feature' }
    end

    before do
      $stdout = StringIO.new
      $stderr = StringIO.new

      @project = double('project')
      @stories = double('stories')
      @story = double('story')
      @pivotal_story = double('pivotal_story', labels: 'label1')
      @menu = double('menu')
      allow(@project).to receive(:stories).and_return(@stories)
      allow(@story).to receive(:pivotal_story).and_return(@pivotal_story)
    end

    describe '.pretty_print' do
      it 'pretty-prints story information' do
        story = double('story')
        expect(story).to receive(:id).and_return(135468)
        expect(story).to receive(:name)
        expect(story).to receive(:description).and_return("description-1\ndescription-2")
        expect(PivotalTracker::Note).to receive(:all).and_return([PivotalTracker::Note.new(:noted_at => Date.new, :text => 'note-1')])

        Story.pretty_print story

        expect($stdout.string).to eq( "         ID: 135468\n" +
                                      "      Title: \n" +
                                      "Description: description-1\n" +
                                      "             description-2\n" +
                                      "     Note 1: note-1\n" +
                                      "\n")
      end

      it 'does not pretty print description or notes if there are none (empty)' do
        story = double('story')
        expect(story).to receive(:id).and_return(135468)
        expect(story).to receive(:name)
        expect(story).to receive(:description)
        expect(PivotalTracker::Note).to receive(:all).and_return([])

        Story.pretty_print story

        expect($stdout.string).to eq( "         ID: 135468\n" +
                                      "      Title: \n" +
                                          "\n")
      end

      it 'does not pretty print description or notes if there are none (nil)' do
        story = double('story')
        expect(story).to receive(:id).and_return(135468)
        expect(story).to receive(:name)
        expect(story).to receive(:description).and_return('')
        expect(PivotalTracker::Note).to receive(:all).and_return([])

        Story.pretty_print story

        expect($stdout.string).to eq( "         ID: 135468\n" +
                                      "      Title: \n" +
                                          "\n")
      end
    end

    describe '.select_story' do
      it 'selects a story directly if the filter is a number' do
        expect(@stories).to receive(:find).with(12345678).and_return(@pivotal_story)
        story = Story.select_story @project, '12345678'

        expect(story).to be_a(Story)
        expect(story.pivotal_story).to eq(@pivotal_story)
      end

      it 'selects a story if the result of the query is a single story' do
        expect(@stories).to receive(:all).with(
            :current_state => %w(rejected unstarted unscheduled),
            :limit => 1,
            :story_type => 'release'
        ).and_return([@pivotal_story])

        story = Story.select_story @project, 'release', 1

        expect(story).to be_a(Story)
        expect(story.pivotal_story).to eq(@pivotal_story)
      end

      it 'prompts the user for a story if the result of the query is more than a single story' do
        expect(@stories).to receive(:all).with(
            :current_state => %w(rejected unstarted unscheduled),
            :limit => 5,
            :story_type => 'feature'
        ).and_return([
                         PivotalTracker::Story.new(:name => 'name-1'),
                         PivotalTracker::Story.new(:name => 'name-2')
                     ])
        expect(@menu).to receive(:prompt=)
        expect(@menu).to receive(:choice).with('name-1')
        expect(@menu).to receive(:choice).with('name-2')
        expect(Story).to receive(:choose) { |&arg| arg.call @menu }.and_return(@pivotal_story)

        story = Story.select_story @project, 'feature'

        expect(story).to be_a(Story)
        expect(story.pivotal_story).to eq(@pivotal_story)
      end

      it 'prompts the user with the story type if no filter is specified' do
        expect(@stories).to receive(:all).with(
            :current_state => %w(rejected unstarted unscheduled),
            :limit => 5,
            :story_type => ['feature', 'bug']
        ).and_return([
                         PivotalTracker::Story.new(:story_type => 'feature', :name => 'name-1'),
                         PivotalTracker::Story.new(:story_type => 'bug', :name => 'name-2')
                     ])
        expect(@menu).to receive(:prompt=)
        expect(@menu).to receive(:choice).with('FEATURE name-1')
        expect(@menu).to receive(:choice).with('BUG     name-2')
        expect(Story).to receive(:choose) { |&arg| arg.call @menu }.and_return(@pivotal_story)

        story = Story.select_story @project

        expect(story).to be_a(Story)
        expect(story.pivotal_story).to eq(@pivotal_story)
      end
    end

    describe '#create_branch!' do
      before do
        allow(@pivotal_story).to receive(:story_type).and_return('feature')
        allow(@pivotal_story).to receive(:id).and_return('123456')
        allow(@pivotal_story).to receive(:name).and_return('test')
        allow(@pivotal_story).to receive(:description).and_return('description')
        @story = GithubPivotalFlow::Story.new(@project, @pivotal_story)
        allow(@story).to receive(:ask).and_return('test')
      end

      it 'prompts the user for a branch extension name' do
        allow(@story).to receive(:branch_prefix).and_return('feature/')
        expect(@story).to receive(:ask).with("Enter branch name (feature/<branch-name>): ").and_return('super-branch')

        @story.create_branch!
      end

      it 'does not create an initial commit' do
        allow(@story).to receive(:branch_name).and_return('feature/123456-my_branch')
        expect(Git).to_not receive(:commit)

        @story.create_branch!
      end

      it 'does not push the local branch' do
        allow(@story).to receive(:branch_name).and_return('feature/123456-my_branch')
        expect(Git).to_not receive(:push)

        @story.create_branch!
      end
    end
    
    describe '#merge_release!' do
      before do
        allow(@pivotal_story).to receive(:story_type).and_return('release')
        allow(@pivotal_story).to receive(:id).and_return('123456')
        allow(@pivotal_story).to receive(:name).and_return('v1.5.1')
        @story = GithubPivotalFlow::Story.new(@project, @pivotal_story)
        allow(@story).to receive(:branch_prefix).and_return('release/')
        allow(@story).to receive(:branch_name).and_return('release/v1.5.1')
      end
      
      context 'if the merge is trivial' do
        before do
          allow(@story).to receive(:trivial_merge?).and_return(true)
        end
        
        it 'merges using fast-forward' do
          expect(Git).to receive(:merge).with('release/v1.5.1', hash_including(ff: true))
          
          @story.merge_release!
        end
      end
      
      context 'with a non-trivial merge' do
        before do
          allow(@story).to receive(:trivial_merge?).and_return(false)
        end
        
        it 'merges using no-ff' do
          expect(Git).to receive(:merge).with('release/v1.5.1', hash_including(no_ff: true))
          
          @story.merge_release!
        end
      end
      
      context 'when the branch is successfully merged' do
        before do
          allow(@story).to receive(:trivial_merge?).and_return(true)
          allow(Git).to receive(:merge).and_return(true)
        end
        
        it 'creates an annotated tag with the release name and short description' do
          expect(Git).to receive(:tag).with('v1.5.1', hash_including(annotated: true, message: 'Release v1.5.1'))
      
          @story.merge_release!
        end
      end
    end

    describe '#merge_to_roots!' do
      context 'with a hotfix story' do
        before do
          allow(@pivotal_story).to receive(:story_type).and_return('bug')
          allow(@pivotal_story).to receive(:id).and_return('123456')
          allow(@pivotal_story).to receive(:name).and_return('fixall')
          allow(@pivotal_story).to receive(:labels).and_return('hotfix')
          @story = GithubPivotalFlow::Story.new(@project, @pivotal_story)
          allow(@story).to receive(:branch_prefix).and_return('hotfix/')
          allow(@story).to receive(:branch_name).and_return('hotfix/fixall')
          allow(@story).to receive(:trivial_merge?).and_return(true)

          allow(@story).to receive(:master_branch_name).and_return('master')
          allow(@story).to receive(:development_branch_name).and_return('development')
        end

        it 'merges back to both the master and the develop branch' do
          expect(Git).to receive(:push).with('master').and_return(nil)
          expect(Git).to receive(:push).with('development').and_return(nil)

          @story.merge_to_roots!
        end
      end
    end

    describe '#master_branch_name' do
      before do
        @story = GithubPivotalFlow::Story.new(@project, @pivotal_story)
        stub_git_branches
      end

      context 'when the story is a hotfix' do
        before do
          allow(@story).to receive(:hotfix?).and_return(true)
        end

        it 'returns the validation branch' do
          expect(@story.master_branch_name).to eq('validation')
        end
      end

      context 'when the story is NOT a hotfix' do
        before do
          allow(@story).to receive(:hotfix?).and_return(false)
        end

        it 'returns the master branch' do
          expect(@story.master_branch_name).to eq('master')
        end
      end
    end

    describe '#hotfix?' do
      before do
        @story = GithubPivotalFlow::Story.new(@project, @pivotal_story)
      end

      context 'when the story is a hotfix' do
        before do
          allow(@pivotal_story).to receive(:labels).and_return('foo,bar,hotfix,baz')
        end

        it 'returns true' do
          expect(@story.hotfix?).to eq(true)
        end
      end

      context 'when the story is NOT a hotfix' do
        before do
          allow(@pivotal_story).to receive(:labels).and_return('foo,bar,baz')
        end

        it 'returns false' do
          expect(@story.hotfix?).to eq(false)
        end
      end
    end

    describe '#params_for_pull_request' do
      before do
        @story = GithubPivotalFlow::Story.new(@project, @pivotal_story)
        allow(@pivotal_story).to receive(:story_type).and_return('bug')
        allow(@pivotal_story).to receive(:name).and_return('pivotal-story-name')
        allow(@pivotal_story).to receive(:description).and_return('pivotal-story-description')
        allow(@story).to receive(:branch_name).and_return('my-branch')
        stub_git_branches
      end

      context 'when the story is a hotfix' do
        before do
          allow(@story).to receive(:hotfix?).and_return(true)
        end

        context 'when for_hotfix is true' do
          it 'returns params with a base of the validation branch' do
            expect(@story.params_for_pull_request(true)[:base]).to eq('validation')
          end
        end

        context 'when for_hotfix is false' do
          it 'returns params with a base of the development branch' do
            expect(@story.params_for_pull_request[:base]).to eq('development')
          end
        end
      end

      context 'when the story is NOT a hotfix' do
        before do
          allow(@story).to receive(:hotfix?).and_return(false)
        end

        it 'returns params with a base of the master branch' do
          expect(@story.params_for_pull_request[:base]).to eq('development')
        end
      end
    end
  end
end
