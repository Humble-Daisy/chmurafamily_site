module LifecycleHelper
  # Sole legal display path for lifecycle state. Never render
  # `record.status.to_s` (titleized or otherwise) — that would leak the
  # internal words "Suspended"/"Discarded" into UI the vocabulary rule
  # reserves for "Locked"/"Deleted".
  def lifecycle_status_label(record)
    t("lifecycle_status.#{record.status}")
  end

  # "Locked" alone doesn't say what is locked, so a screen reader also hears the
  # prefix; aria-label on a role-less span is ignored, hence sr-only text.
  def lifecycle_status_badge(record, **attrs)
    label = lifecycle_status_label(record)
    ui :badge, variant: :soft, tone: (record.suspended? ? :warning : :neutral), **attrs do
      safe_join([ tag.span("#{t('lifecycle_status.prefix')}: ", class: "sr-only"), label ])
    end
  end
end
