# Tekton Pipeline Tutorial - Example Files

This directory contains example files for the Tekton Pipeline Local Tutorial.

## Files

- `webhook-server.py` - Python webhook server that receives GitHub webhooks and triggers Tekton pipelines
- `pipeline.yaml` - Tekton Pipeline definition
- `serviceaccount.yaml` - Service account with DockerHub and GitHub secrets
- `Dockerfile` - Simple example Dockerfile
- `README.md` - This file

## Quick Start

1. **Set up your environment:**
   ```bash
   export DOCKERHUB_USERNAME=your-dockerhub-username
   export DOCKERHUB_PASSWORD=your-dockerhub-password
   export GITHUB_USERNAME=your-github-username
   export GITHUB_TOKEN=your-github-token
   ```

2. **Update serviceaccount.yaml:**
   - Replace `YOUR_DOCKERHUB_USERNAME` with your DockerHub username
   - Replace `YOUR_DOCKERHUB_PASSWORD` with your DockerHub password
   - Replace `YOUR_GITHUB_USERNAME` with your GitHub username
   - Replace `YOUR_GITHUB_TOKEN` with your GitHub personal access token

3. **Update pipeline.yaml:**
   - Replace `YOUR_USERNAME` with your GitHub username in the git-clone task URL

4. **Apply Tekton resources:**
   ```bash
   kubectl apply -f serviceaccount.yaml
   kubectl apply -f pipeline.yaml
   ```

5. **Start webhook server:**
   ```bash
   python3 webhook-server.py
   ```

6. **Expose with ngrok:**
   ```bash
   ngrok http 8080
   ```

7. **Configure GitHub webhook:**
   - Use the ngrok URL as the webhook payload URL

8. **Create and push a tag:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

9. **Watch the pipeline:**
   ```bash
   kubectl get pipelineruns -w
   tkn pipelinerun logs <pipelinerun-name> -f
   ```

## For More Details

See the full tutorial: `../TEKTON-PIPELINE-LOCAL-TUTORIAL.md`

