#!/usr/bin/env python3
"""
Simple webhook server for Tekton pipeline tutorial.
Receives GitHub webhooks and triggers Tekton PipelineRuns.
"""
import http.server
import json
import subprocess
import os
import sys
from datetime import datetime

# Configuration
DOCKERHUB_USERNAME = os.getenv('DOCKERHUB_USERNAME', 'YOUR_DOCKERHUB_USERNAME')
PIPELINE_NAME = 'build-and-push-pipeline'
SERVICE_ACCOUNT = 'tekton-pipeline-sa'
IMAGE_NAME = 'tekton-tutorial'

class WebhookHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        """Override to add timestamp"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp}] {format % args}")
    
    def do_GET(self):
        """Handle GET requests (health check)"""
        self.send_response(200)
        self.send_header('Content-type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'Webhook server is running!\n')
        self.wfile.write(b'Waiting for GitHub tag push events...\n')
    
    def do_POST(self):
        """Handle POST requests from GitHub"""
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        
        try:
            data = json.loads(post_data.decode('utf-8'))
            
            # Extract ref (branch or tag)
            ref = data.get('ref', '')
            repository = data.get('repository', {})
            repo_name = repository.get('name', 'unknown')
            pusher = data.get('pusher', {})
            pusher_name = pusher.get('name', 'unknown')
            
            self.log_message(f"Received webhook: ref={ref}, repo={repo_name}, pusher={pusher_name}")
            
            # Check if it's a tag push
            if ref.startswith('refs/tags/'):
                tag = ref.replace('refs/tags/', '')
                self.log_message(f"✅ Tag detected: {tag}")
                
                # Trigger pipeline
                success = self.trigger_pipeline(tag, repo_name)
                
                if success:
                    self.send_response(200)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    response = {
                        'status': 'success',
                        'message': f'Pipeline triggered for tag: {tag}',
                        'tag': tag
                    }
                    self.wfile.write(json.dumps(response).encode())
                    self.log_message(f"✅ Pipeline triggered successfully for tag: {tag}")
                else:
                    self.send_response(500)
                    self.send_header('Content-type', 'application/json')
                    self.end_headers()
                    response = {
                        'status': 'error',
                        'message': 'Failed to trigger pipeline'
                    }
                    self.wfile.write(json.dumps(response).encode())
                    self.log_message(f"❌ Failed to trigger pipeline for tag: {tag}")
            else:
                self.log_message(f"⏭️  Ignoring non-tag push: {ref}")
                self.send_response(200)
                self.send_header('Content-type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'status': 'ignored', 'reason': 'not a tag'}).encode())
                
        except json.JSONDecodeError as e:
            self.log_message(f"❌ JSON decode error: {e}")
            self.send_response(400)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'error', 'message': 'Invalid JSON'}).encode())
        except Exception as e:
            self.log_message(f"❌ Error processing webhook: {e}")
            self.send_response(500)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'error', 'message': str(e)}).encode())
    
    def trigger_pipeline(self, tag, repo_name):
        """Create a PipelineRun for the tag"""
        try:
            # Sanitize tag name for Kubernetes resource name
            safe_tag = tag.replace('.', '-').replace('_', '-').lower()
            pipelinerun_name = f"build-and-push-{safe_tag}"
            
            # Create PipelineRun YAML
            pipelinerun_yaml = f"""apiVersion: tekton.dev/v1beta1
kind: PipelineRun
metadata:
  name: {pipelinerun_name}
  labels:
    app: tekton-tutorial
    tag: {tag}
spec:
  pipelineRef:
    name: {PIPELINE_NAME}
  serviceAccountName: {SERVICE_ACCOUNT}
  params:
    - name: git-tag
      value: "{tag}"
    - name: image-name
      value: "{IMAGE_NAME}"
    - name: image-tag
      value: "{tag}"
    - name: dockerhub-username
      value: "{DOCKERHUB_USERNAME}"
    - name: dockerhub-password
      value: ""
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes:
            - ReadWriteOnce
          resources:
            requests:
              storage: 1Gi
"""
            
            # Write to temporary file
            temp_file = f'/tmp/pipelinerun-{safe_tag}.yaml'
            with open(temp_file, 'w') as f:
                f.write(pipelinerun_yaml)
            
            self.log_message(f"📝 Created PipelineRun YAML: {temp_file}")
            
            # Apply using kubectl
            result = subprocess.run(
                ['kubectl', 'apply', '-f', temp_file],
                capture_output=True,
                text=True,
                timeout=10
            )
            
            if result.returncode == 0:
                self.log_message(f"✅ PipelineRun created: {pipelinerun_name}")
                self.log_message(f"📋 Output: {result.stdout.strip()}")
                return True
            else:
                self.log_message(f"❌ Failed to create PipelineRun: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            self.log_message("❌ kubectl command timed out")
            return False
        except Exception as e:
            self.log_message(f"❌ Error triggering pipeline: {e}")
            return False

def main():
    port = int(os.getenv('PORT', 8080))
    
    if DOCKERHUB_USERNAME == 'YOUR_DOCKERHUB_USERNAME':
        print("⚠️  WARNING: DOCKERHUB_USERNAME not set!")
        print("   Set it with: export DOCKERHUB_USERNAME=your-username")
        print("   Or edit this file and set DOCKERHUB_USERNAME variable")
        print()
    
    server = http.server.HTTPServer(('', port), WebhookHandler)
    print("=" * 60)
    print("🚀 Tekton Webhook Server")
    print("=" * 60)
    print(f"📡 Listening on port {port}")
    print(f"🌐 Use ngrok to expose: ngrok http {port}")
    print(f"📦 DockerHub username: {DOCKERHUB_USERNAME}")
    print(f"🔧 Pipeline: {PIPELINE_NAME}")
    print("=" * 60)
    print("Waiting for GitHub webhooks...")
    print("Press Ctrl+C to stop")
    print()
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n\n👋 Shutting down webhook server...")
        server.shutdown()
        sys.exit(0)

if __name__ == '__main__':
    main()

