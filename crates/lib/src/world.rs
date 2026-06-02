//! The world model and its tick rule.
//!
//! The world holds only mutable simulation state; the rules for advancing it
//! read their tunables from [`GameData`], so a saved world plus its content set
//! is enough to resume deterministically.

use crate::data::GameData;
use serde::{Deserialize, Serialize};

/// A settlement and its inhabitants at a point in simulated time.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct World {
  pub tick: u64,
  pub settlement_name: String,
  pub individuals: Vec<Individual>,
}

/// A single inhabitant.  `archetype` references content in [`GameData`] rather
/// than copying its tunables, so changing the content changes behavior without
/// rewriting saves.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Individual {
  pub id: u32,
  pub name: String,
  pub archetype: String,
  pub satiation: i32,
}

impl World {
  /// Build the initial world described by the scenario, seeding each
  /// inhabitant's satiation from its archetype.
  pub fn new(data: &GameData) -> Self {
    Self {
      tick: 0,
      settlement_name: data.scenario.settlement_name.clone(),
      individuals: data
        .scenario
        .individuals
        .iter()
        .enumerate()
        .map(|(index, spec)| Individual {
          id: index as u32,
          name: spec.name.clone(),
          archetype: spec.archetype.clone(),
          satiation: data
            .archetype(&spec.archetype)
            .map_or(0, |a| a.max_satiation),
        })
        .collect(),
    }
  }

  /// Advance the world by one tick: every inhabitant grows hungrier at its
  /// archetype's rate, clamped at zero.
  pub fn advance(&mut self, data: &GameData) {
    self.tick += 1;
    self.individuals.iter_mut().for_each(|individual| {
      let rate = data
        .archetype(&individual.archetype)
        .map_or(0, |a| a.hunger_rate);
      individual.satiation = (individual.satiation - rate).max(0);
    });
  }

  /// Advance the world by `count` ticks.
  pub fn advance_by(&mut self, data: &GameData, count: u64) {
    (0..count).for_each(|_| self.advance(data));
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::data::{ArchetypeDef, Scenario, ScenarioIndividual};

  fn sample_data() -> GameData {
    GameData {
      archetypes: vec![ArchetypeDef {
        id: "forager".to_string(),
        name: "Forager".to_string(),
        max_satiation: 100,
        hunger_rate: 2,
      }],
      scenario: Scenario {
        settlement_name: "Cedar Hollow".to_string(),
        individuals: vec![
          ScenarioIndividual {
            name: "Tahoma".to_string(),
            archetype: "forager".to_string(),
          },
          ScenarioIndividual {
            name: "Kwina".to_string(),
            archetype: "forager".to_string(),
          },
        ],
      },
    }
  }

  #[test]
  fn new_seeds_from_archetype() {
    let world = World::new(&sample_data());
    assert_eq!(world.tick, 0);
    assert_eq!(world.individuals.len(), 2);
    assert!(world.individuals.iter().all(|i| i.satiation == 100));
    assert_eq!(world.individuals[0].id, 0);
    assert_eq!(world.individuals[1].id, 1);
  }

  #[test]
  fn advance_is_deterministic() {
    let data = sample_data();
    let mut world = World::new(&data);
    world.advance_by(&data, 10);
    assert_eq!(world.tick, 10);
    assert!(world.individuals.iter().all(|i| i.satiation == 80));
  }

  #[test]
  fn satiation_clamps_at_zero() {
    let data = sample_data();
    let mut world = World::new(&data);
    world.advance_by(&data, 1000);
    assert!(world.individuals.iter().all(|i| i.satiation == 0));
  }
}
