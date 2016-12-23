require 'spec_helper'

module GithubPivotalFlow
  describe Publish do
    let(:fake_git) { double('Git').as_null_object }

    before do
      $stdout = StringIO.new
      $stderr = StringIO.new

      @project = double('project')
      @story = double('story',
        branch_name: 'feature/1234-sample_story',
        release?: false,
        params_for_pull_request: {},
        hotfix?: false
      )
      @ghclient = double('ghclient')
      @ghproject = double('ghproject')
      @configuration = double('configuration',
        development_branch: 'development',
        master_branch: 'master',
        feature_prefix: 'feature/',
        hotfix_prefix: 'hotfix/',
        release_prefix: 'release/',
        api_token: 'token',
        project_id: '123',
        project: @project,
        github_client: @ghclient,
        story: @story,
        validate: true
      )
      allow(Configuration).to receive(:new).and_return(@configuration)
      allow(Project).to receive(:find).and_return(@project)
      allow(@ghclient).to receive(:create_pullrequest).and_return(true)
      allow(Git).to receive(:push).and_return(true)
      @publish = Publish.new
    end

    it 'fails if we cannot find the story this branch relates to' do
      allow(@configuration).to receive(:story).and_return(nil)
      expect { @publish.run! }.to raise_error("Could not find story associated with branch")
    end

    it 'fails with a dirty working tree' do
      expect(Git).to receive(:clean_working_tree?).and_raise(RuntimeError)
      expect { @publish.run! }.to raise_error(RuntimeError)
    end

    context 'with a clean working tree' do
      before do
        allow(Git).to receive(:clean_working_tree?).and_return(true)

      end

      it 'pushes the branch back to the origin and sets the upstream' do
        expect(Git).to receive(:push).with(instance_of(String), hash_including(set_upstream: true)).and_return(true)

        @publish.run!
      end

      it 'opens a pull request' do
        expect(@ghclient).to receive(:create_pullrequest).and_return(true)

        @publish.run!
      end

      context 'when the story is  hotfix' do
        let(:validation_branch_params) do
          {
            base: 'validation',
            head: 'branch_name',
            title: 'name',
            body: 'description',
          }
        end

        let(:master_branch_params) do
          {
            base: 'master',
            head: 'branch_name',
            title: 'name',
            body: 'description',
          }
        end

        before do
          allow(@story).to receive(:hotfix?).and_return(true)
          expect(@story).to receive(:params_for_pull_request).with(no_args).and_return(master_branch_params)
          expect(@story).to receive(:params_for_pull_request).with(true).and_return(validation_branch_params)
        end

        it 'pushes the branch back to the origin and sets the upstream' do
          expect(Git).to receive(:push).with(instance_of(String), hash_including(set_upstream: true)).and_return(true)

          @publish.run!
        end

        it 'opens a pull request against the validation branch' do
          expect(@ghclient).to receive(:create_pullrequest).with(hash_including(validation_branch_params)).and_return(true)

          @publish.run!
        end

        it 'opens a pull request against the master branch' do
          expect(@ghclient).to receive(:create_pullrequest).with(hash_including(master_branch_params)).and_return(true)

          @publish.run!
        end
      end
    end
  end
end
