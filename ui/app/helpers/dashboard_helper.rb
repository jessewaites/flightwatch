module DashboardHelper
  def anomaly_dom_id(anomaly)
    "anomaly_#{anomaly[:id].to_s.parameterize(separator: "_")}"
  end

  def situation_dom_id(situation)
    "situation_#{situation["id"].to_s.parameterize(separator: "_")}"
  end

  def timestamp_label(ts)
    return "pending" if ts.blank?

    Time.at(ts.to_i).utc.strftime("%H:%M:%SZ")
  end

  def evidence_label(evidence)
    evidence.to_h.map { |key, value| "#{key}: #{value}" }.join(" | ")
  end
end
