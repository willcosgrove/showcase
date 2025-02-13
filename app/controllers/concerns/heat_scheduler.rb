module HeatScheduler
  include Printable
  
  def schedule_heats
    Group.set_knobs

    # remove all scratches and orphaned entries
    Heat.where(number: ...0).each {|heat| heat.destroy}
    Entry.includes(:heats).where(heats: {id: nil}).each {|entry| entry.destroy}

    # extract heats
    @heats = Heat.eager_load(
      :solo,
      dance: [:open_category, :closed_category, :solo_category, :multi_category],
      entry: [{lead: :studio}, {follow: :studio}]
    )

    # convert relevant data to numbers
    heat_categories = {'Closed' => 0, 'Open' => 1, 'Solo' => 2, 'Multi' => 3}
    routines = Category.where(routines: true).all.zip(4..).map {|cat, num| [cat.id, num]}.to_h

    heats = @heats.map {|heat|
      if heat.solo&.category_override_id
        category = routines[heat.solo.category_override_id]
        order = 1000 + heat.solo.order
      else
        category = heat_categories[heat.category]
        order = heat.dance.order
      end

      [order,
       category,
       heat.entry.level_id,
       heat.entry.age_id,
       heat
      ]}

    heats = Group.sort(heats)

    max = Event.last.max_heat_size || 9999

    # group entries into heats
    groups = []
    while not heats.empty?
      Group.max = 9999

      assignments = {}
      subgroups = []

      more = heats.first
      while more
        group = Group.new
        subgroups.unshift group
        more = nil

        heats.each_with_index do |entry, index|
          next if assignments[index]
          if group.add? *entry
            assignments[index] = group
          elsif group.match? *entry
            more ||= entry
          else
            break
          end
        end
      end

      Group.max = group.max_heat_size
      assignments = (0...assignments.length).map {|index| [heats[index], assignments[index]]}.to_h
      rebalance(assignments, subgroups, group.max_heat_size)

      heats.shift assignments.length
      groups += subgroups.reverse
    end

    groups = reorder(groups)

    ActiveRecord::Base.transaction do
      groups.each_with_index do |group, index|
        group.each do |heat|
          heat.number = index + 1
          heat.save validate: false
        end
      end
    end

    @stats = groups.each_with_index.
      map {|group, index| [group, index+1]}.
      group_by {|group, heat| group.size}.
      map {|size, entries| [size, entries.map(&:last)]}.
      sort

    @heats = @heats.
      group_by {|heat| heat.number}.map do |number, heats|
        [number, heats.sort_by { |heat| heat.back || 0 } ]
      end.sort
  end

  def rebalance(assignments, subgroups, max)
    while subgroups.length * max < assignments.length
      subgroups.unshift Group.new
    end

    ceiling = (assignments.length.to_f / subgroups.length).ceil
    floor = (assignments.length.to_f / subgroups.length).floor

    assignments.to_a.reverse.each do |(entry, source)|
      subgroups.each do |target|
        break if target == source
        next if target.size >= ceiling
        next if target.size >= source.size

        if target.add? *entry
          source.remove *entry
          assignments[entry] = target
          break
        end
      end
    end

    subgroups.select {|subgroup| subgroup.size < floor}.each do |target|
      assignments.each do |entry, source|
        next if source.size < max
        if target.add? *entry
          source.remove *entry
          assignments[entry] = target
          break if target.size >= max
        end
      end
    end

    if subgroups.any? {|subgroup| subgroup.size > max}
      assignments.each do |entry, target|
        next if target.size >= max
        subgroups.each do |source|
          next if source.size <= max
          if target.add? *entry
            source.remove *entry
            assignments[entry] = target
            break if target.size >= max
          end
        end
      end

      if subgroups.any? {|subgroup| subgroup.size > max}
        subgroups.unshift Group.new
        rebalance(assignments, subgroups, max)
      end
    end
  end

  def reorder(groups)
    categories = Category.order(:order).all
    cats = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h
    solos = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h
    multis = (categories.map {|cat| [cat, []]} + [[nil, []]]).to_h

    groups.each do |group|
      dcat = group.dcat

      if dcat == 'Open'
        cats[group.dance.open_category] << group
      elsif dcat == 'Solo'
        solos[group.dance.solo_category] << group
      elsif dcat == 'Multi'
        multis[group.dance.multi_category] << group
      else
        cats[group.override || group.dance.closed_category] << group
      end
    end

    new_order = []
    agenda = {}

    cats.each do |cat, groups|
      if Event.last.intermix
        dances = groups.group_by {|group| [group.dcat, group.dance.order]}
        candidates = []

        max = dances.values.map(&:length).max || 1
        offset = 0.5/(max + 1)

        dances.each do |id, groups|
          denominator = groups.length.to_f + 1
          groups.each_with_index do |group, index|
            slot = (((index+1.0)/denominator - offset)/offset/2).to_i
            candidates << [slot] + id + [group]
          end
        end

        groups = candidates.sort_by {|candidate| candidate[0..2]}.map(&:last)
      end

      groups +=
        solos[cat].sort_by {|group| group.first.solo.order} +
        multis[cat]

      if cat
        if cat.heats and groups.length > cat.heats
          extensions_needed = 1 # (groups.length.to_f / cat.heats).ceil - 1
        else
          extensions_needed = 0
        end

        extensions_found = cat.extensions.order(:part).all.to_a

        while extensions_found.length > extensions_needed
          extensions_found.pop.destroy!
        end

        while extensions_needed > extensions_found.length
          order = [Category.maximum(:order), CatExtension.maximum(:order)].compact.max + 1
          extensions_found << CatExtension.create!(category: cat, order: order, part: extensions_found.length + 2)
        end

        if extensions_needed > 0
          agenda[extensions_found.first] = groups[cat.heats..]
          groups = groups[..cat.heats-1]
        end
      end

      agenda[cat] = groups
    end

    cats = agenda.to_a.sort_by {|cat, groups| cat&.order || 999}.to_h

    heat = 1
    cats.each do |cat, groups|
      if cat.instance_of? CatExtension
        cat.update! start_heat: heat
      end

      heat += groups.length
    end

    cats.values.flatten
  end

  class Group
    def self.set_knobs
      @@event = Event.last
      @@category = @@event.heat_range_cat
      @@level = @@event.heat_range_level
      @@age = @@event.heat_range_age
      @@max = @@event.max_heat_size || 9999
    end

    def self.max= max
      @@max = max
    end

    def self.sort(heats)
      if @@category == 0
        heats.sort_by {|heat| heat[0..1].reverse + heat[2..-1]}
      else
        heats.sort
      end
    end

    def dance
      @group.first.dance
    end

    def override
      @group.first.solo&.category_override
    end

    def dcat
      case @min_dcat
      when 0
        'Closed'
      when 1
        'Open'
      when 2
        'Solo'
      when 3
        'Multi'
      else
        '?'
      end
    end

    def max_heat_size
      agenda_cat = case @min_dcat
      when 0
        dance&.closed_category
      when 1
        dance&.open_category
      when 2
        dance&.solo_category
      when 3
        dance&.multi_category
      else
        nil
      end

      agenda_cat&.max_heat_size || @@event.max_heat_size || 9999
    end

    def initialize
      @group = []
    end

    def match?(dance, dcat, level, age, heat)
      return false unless @dance == dance
      return false unless @dcat == dcat or @@category > 0
      return false if heat.category == 'Solo'
      return true
    end

    def add?(dance, dcat, level, age, heat)
      if @group.length == 0
        @participants = Set.new
  
        @max_dcat = @min_dcat = dcat
        @max_level = @min_level = level
        @max_age = @min_age = age
        
        @dance = dance
        @dcat = dcat
      end

      return if @group.size >= @@max
      return if @participants.include? heat.lead
      return if @participants.include? heat.follow
      return if heat.lead.exclude_id and @participants.include? heat.lead.exclude
      return if heat.follow.exclude_id and @participants.include? heat.follow.exclude

      return false unless @dance == dance
      return false if heat.category == 'Solo' and @group.length > 0
      return false unless (dcat-@max_dcat).abs <= @@category
      return false unless (dcat-@min_dcat).abs <= @@category
      return false unless (level-@max_level).abs <= @@level
      return false unless (level-@min_level).abs <= @@level
      return false unless (age-@max_age).abs <= @@age
      return false unless (age-@min_age).abs <= @@age

      @participants.add heat.lead
      @participants.add heat.follow

      @max_dcat = dcat if dcat > @max_dcat
      @min_dcat = dcat if dcat < @min_dcat
      @min_level = level if level < @min_level
      @max_level = level if level > @max_level
      @min_age = age if age < @min_age
      @max_age = age if age > @max_age

      @group << heat
    end

    def remove(dance, dcat, level, age, heat)
      @group.delete heat
      @participants.delete heat.lead
      @participants.delete heat.follow
    end

    def each(&block)
      @group.each(&block)
    end

    def first
      @group.first
    end

    def size
      @group.size
    end
  end
end
