class AlertsAppController < ApplicationController
  def index
    path = Rails.root.join("public/alerts-ui/index.html")
    if path.file?
      render file: path, layout: false, content_type: "text/html"
    else
      render plain: "Build the alerts interface with npm ci && npm run build, then refresh this page.", status: :service_unavailable
    end
  end
end
