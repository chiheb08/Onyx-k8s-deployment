FROM nginx:alpine

# Add a simple HTML page that shows the tag
RUN echo '<!DOCTYPE html>' > /usr/share/nginx/html/index.html && \
    echo '<html><head><title>Tekton Pipeline Test</title></head>' >> /usr/share/nginx/html/index.html && \
    echo '<body style="font-family: Arial, sans-serif; text-align: center; padding: 50px;">' >> /usr/share/nginx/html/index.html && \
    echo '<h1>Hello from Tekton Pipeline!</h1>' >> /usr/share/nginx/html/index.html && \
    echo '<p>This image was built and pushed by Tekton Pipeline</p>' >> /usr/share/nginx/html/index.html && \
    echo '<p>Tag: ${TAG:-unknown}</p>' >> /usr/share/nginx/html/index.html && \
    echo '<p>Build time: $(date)</p>' >> /usr/share/nginx/html/index.html && \
    echo '</body></html>' >> /usr/share/nginx/html/index.html

# Expose port 80
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]

